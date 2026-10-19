#!/bin/bash
# PROJ-040: scripts/mailbox-passwd.sh against a fixture passwords file.
# Run by goss/repo.yaml; offline.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

TOOL=scripts/mailbox-passwd.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

OTHER='other@example.org:$6$x$untouched'
TARGET=canary@example.org
fixture() {
    printf '%s\n' '# comment kept' "$OTHER" "$TARGET:\$6\$old\$oldhash" > "$work/passwords"
    chmod 0640 "$work/passwords"
}
hash_of() { awk -v a="$1" 'index($0, a ":") == 1 { print substr($0, length(a) + 2) }' "$work/passwords"; }
verifies() {  # password hash
    local salt; salt=$(cut -d'$' -f3 <<<"$2")
    [[ "$2" == '$6$'* ]] && [ "$(printf '%s\n' "$1" | openssl passwd -6 -salt "$salt" -stdin)" = "$2" ]
}

# --- --random FILE on an existing address --------------------------------------
fixture
if PASSWORDS="$work/passwords" "$TOOL" --random "$work/pw" "$TARGET" > "$work/out" 2>&1; then
    ok "--random FILE succeeds"
else
    bad "--random FILE failed:"; sed 's/^/        /' "$work/out"
fi
pw=$(cat "$work/pw" 2>/dev/null)
[ "${#pw}" -eq 32 ] && ok "the password is 32 characters" || bad "password length ${#pw}"
[ "$(stat -c %a "$work/pw")" = 600 ] && ok "the password file is 0600" || bad "password file mode $(stat -c %a "$work/pw")"
verifies "$pw" "$(hash_of "$TARGET")" && ok "the new hash is SHA-512 crypt of the written password" \
    || bad "the new hash does not verify against the written password"
grep -qxF "$OTHER" "$work/passwords" && grep -qxF '# comment kept' "$work/passwords" \
    && ok "other lines are untouched" || bad "other lines changed"
[ "$(grep -c "^$TARGET:" "$work/passwords")" -eq 1 ] && ok "the address has exactly one line" \
    || bad "the address has $(grep -c "^$TARGET:" "$work/passwords") lines"
[ "$(stat -c %a "$work/passwords")" = 640 ] && ok "the passwords file keeps its mode" \
    || bad "passwords file mode became $(stat -c %a "$work/passwords")"
grep -qF -- "$pw" "$work/out" && bad "the password appears in the output" || ok "the password is not in the output"
[ -z "$(find "$work" -name '.passwords.*' -o -name '.mailbox-passwd.*')" ] && ok "no temporary files are left" \
    || bad "temporary files left"

# --- --random - on a new address, into a new file ------------------------------
rm -f "$work/new"
if PASSWORDS="$work/new" "$TOOL" --random - letsencrypt@example.org > "$work/out" 2>&1 \
   && grep -q '^letsencrypt@example.org:\$6\$' "$work/new" && [ "$(stat -c %a "$work/new")" = 600 ] \
   && [ -z "$(find "$work" -maxdepth 1 -newer "$work/new" -name 'pw*')" ]; then
    ok "--random - adds the address to a new 0600 file and keeps no password"
else
    bad "--random - on a new file:"; sed 's/^/        /' "$work/out"
fi

# --- refusals that write nothing -----------------------------------------------
fixture; cp "$work/passwords" "$work/before"
if PASSWORDS="$work/passwords" "$TOOL" --random - Canary@example.org > "$work/out" 2>&1; then
    bad "accepted an uppercase address"
elif cmp -s "$work/before" "$work/passwords"; then
    ok "refused an uppercase address, nothing written"
else
    bad "refused an uppercase address but changed the file"
fi
if PASSWORDS="$work/passwords" "$TOOL" "$TARGET" < /dev/null > "$work/out" 2>&1; then
    bad "prompted without a terminal"
elif cmp -s "$work/before" "$work/passwords"; then
    ok "refused to prompt without a terminal, nothing written"
else
    bad "refused to prompt but changed the file"
fi

exit "$fail"
