#!/bin/bash
# PROJ-040: scripts/userdb-source.sh derives the userdb source from the
# context's mailboxes and the passwords file. Run by goss/repo.yaml; offline.
#
# userdb.template is taken from deployment/k8s/configmap.yaml, so this tests
# what ships, against the example context (mailboxes canary@ and
# letsencrypt@the-domain.com).

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

EXAMPLE=examples/example-context.json
RENDERER=$(scripts/fetch-renderer.sh "$EXAMPLE") || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
python3 -I -c 'import sys, yaml
open(sys.argv[2], "w").write(yaml.safe_load(open(sys.argv[1]))["data"]["userdb.template"])' \
    deployment/k8s/configmap.yaml "$work/userdb.template" || exit 1

fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
run() { scripts/userdb-source.sh "$RENDERER" "$work/userdb.template" "$EXAMPLE" "$work/passwords" > "$work/out" 2> "$work/err"; }

C='$6$saltc$hashcanary'
L='$6$saltl$hashletsencrypt'
T=$'\t'

# --- the normal case -----------------------------------------------------------
printf '%s\n' '# hashes' "letsencrypt@the-domain.com:$L" "canary@the-domain.com:$C" > "$work/passwords"
cat > "$work/want" <<EOF
canary@the-domain.com${T}uid=300|gid=300|home=/vmail/the-domain.com/canary|mail=/vmail/the-domain.com/canary/Maildir|systempw=$C
letsencrypt@the-domain.com${T}uid=300|gid=300|home=/vmail/the-domain.com/letsencrypt|mail=/vmail/the-domain.com/letsencrypt/Maildir|systempw=$L
EOF
if run && diff -u "$work/want" "$work/out" > "$work/diff"; then
    ok "one record per mailbox, with the derived fields and its hash"
else
    bad "unexpected userdb source:"; sed 's/^/        /' "$work/err" "$work/diff"
fi

# --- disagreements: refused, naming the address, never printing a hash ---------
# name | passwords lines (";" separated) | address the error must name
while IFS='|' read -r name lines who; do
    [ -n "$name" ] || continue
    tr ';' '\n' <<<"$lines" > "$work/passwords"
    if run; then
        bad "accepted: $name"
    elif ! grep -qF "$who" "$work/err"; then
        bad "refused without naming $who: $name"; sed 's/^/        /' "$work/err"
    elif grep -qE 'hash(canary|letsencrypt|stray)' "$work/err"; then
        bad "a hash appears in the error: $name"
    else
        ok "refused, naming $who: $name"
    fi
done <<EOF
a mailbox with no hash|canary@the-domain.com:$C|letsencrypt@the-domain.com
a hash for an undeclared mailbox|canary@the-domain.com:$C;letsencrypt@the-domain.com:$L;gone@the-domain.com:\$6\$s\$hashstray|gone@the-domain.com
an address with two hashes|canary@the-domain.com:$C;canary@the-domain.com:$C;letsencrypt@the-domain.com:$L|canary@the-domain.com
EOF

exit "$fail"
