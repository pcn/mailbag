#!/bin/bash
# PROJ-039: scripts/rotate-canary-password.sh against a fixture userdb source.
# Run by goss/repo.yaml; offline, no host.
#
#   - only the canary's systempw changes; the other record and the canary's
#     other fields are byte-identical
#   - the new hash is SHA-512 crypt and verifies against the written password
#   - the password file is 0600 and the source keeps its mode
#   - the password is not in the script's output
#   - a missing canary, a record without systempw, or two records for the
#     canary fail before anything is written

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

ROTATE=scripts/rotate-canary-password.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

CANARY=canary@example.org
OLD='$6$oldsalt$oldhasholdhasholdhash'
fixture() {  # dir [canary record fields]
    mkdir -p "$1"
    printf '%s\t%s\n' \
        "$CANARY" "${2:-uid=300|home=/vmail/example.org/canary|mail=/vmail/example.org/canary/Maildir|gid=300|systempw=$OLD}" \
        "other@example.org" "uid=300|home=/vmail/example.org/other|gid=300|systempw=\$6\$x\$untouched" \
        > "$1/example.org"
    chmod 0640 "$1/example.org"
}

# --- the normal case ---------------------------------------------------------
fixture "$work/db"
cp "$work/db/example.org" "$work/before"
if "$ROTATE" "$work/db" "$CANARY" "$work/pw" > "$work/out" 2>&1; then
    ok "rotation succeeds on a valid source"
else
    bad "rotation failed:"; sed 's/^/        /' "$work/out"
fi
pw=$(cat "$work/pw" 2>/dev/null)

[ "${#pw}" -eq 32 ] && ok "the password is 32 characters" || bad "password length ${#pw}"
[ "$(stat -c %a "$work/pw")" = 600 ] && ok "the password file is 0600" \
    || bad "password file mode $(stat -c %a "$work/pw")"
[ "$(stat -c %a "$work/db/example.org")" = 640 ] && ok "the source keeps its mode" \
    || bad "source mode became $(stat -c %a "$work/db/example.org")"
if [ -n "$pw" ] && grep -qF -- "$pw" "$work/out"; then
    bad "the password appears in the output"
else
    ok "the password is not in the output"
fi

diff <(sed 's/systempw=[^|]*$/systempw=X/; s/systempw=[^|]*|/systempw=X|/' "$work/before") \
     <(sed 's/systempw=[^|]*$/systempw=X/; s/systempw=[^|]*|/systempw=X|/' "$work/db/example.org") \
     > /dev/null && ok "nothing but systempw values changed" || bad "fields other than systempw changed"
grep -qF 'other@example.org	uid=300|home=/vmail/example.org/other|gid=300|systempw=$6$x$untouched' \
    "$work/db/example.org" && ok "the other account is untouched" || bad "the other account changed"

new=$(awk -F'\t' -v u="$CANARY" '$1 == u' "$work/db/example.org" | grep -o 'systempw=[^|]*' | cut -d= -f2-)
salt=$(cut -d'$' -f3 <<<"$new")
if [[ "$new" == '$6$'* ]] && [ "$new" != "$OLD" ] \
   && [ "$(printf '%s\n' "$pw" | openssl passwd -6 -salt "$salt" -stdin)" = "$new" ]; then
    ok "the canary's new hash is SHA-512 crypt of the written password"
else
    bad "the canary's systempw is not SHA-512 crypt of the written password"
fi
[ -z "$(find "$work/db" -name '.rotate.*')" ] && ok "no temporary files are left" \
    || bad "temporary files left in the userdb directory"

# --- cases that must refuse, writing nothing ---------------------------------
# name | canary record fields ("" = the normal record) | canary to ask for
while IFS='|' read -r name fields ask; do
    [ -n "$name" ] || continue
    d="$work/case-${name// /-}"
    fixture "$d" "${fields//;/|}"
    [ "$name" = "two records for the canary" ] && printf '%s\tuid=1|systempw=$6$y$z\n' "$CANARY" >> "$d/example.org"
    cp "$d/example.org" "$d.before"
    if "$ROTATE" "$d" "$ask" "$d.pw" > "$d.out" 2>&1; then
        bad "accepted: $name"
    elif ! cmp -s "$d.before" "$d/example.org" || [ -e "$d.pw" ]; then
        bad "refused but wrote something: $name"
    else
        ok "refused, nothing written: $name"
    fi
done <<EOF
canary not in the source||nobody@example.org
canary record without systempw|uid=300;home=/vmail/example.org/canary;gid=300|$CANARY
two records for the canary||$CANARY
EOF

exit "$fail"
