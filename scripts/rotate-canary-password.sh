#!/bin/bash
# Give the canary account a fresh random password.
#
#   scripts/rotate-canary-password.sh USERDB_DIR CANARY PASSWORD_FILE
#
# USERDB_DIR is the userdb source directory (<config.authlib_path>/userdb on
# the host), CANARY the userdb.canary address. Replaces only the systempw
# field of the canary's record with a SHA-512 crypt hash (openssl passwd -6;
# userdbpw is not on the node), keeping the file's owner and mode, and writes
# the password to PASSWORD_FILE (0600). The change is published by the next
# deploy, whose database build job runs makeuserdb -- scripts/node-test.sh
# calls this right before deploying.
#
# The password is never printed and never on a command line: it reaches
# openssl on stdin and the hash reaches awk through the environment. Nothing
# is written unless the canary has exactly one record with a systempw field.
#
# PROJ-039.

set -e -u -o pipefail

dir="${1:?usage: $0 USERDB_DIR CANARY PASSWORD_FILE}"
canary="${2:?usage: $0 USERDB_DIR CANARY PASSWORD_FILE}"
pwfile="${3:?usage: $0 USERDB_DIR CANARY PASSWORD_FILE}"

die() { echo "rotate-canary-password: $*" >&2; exit 1; }
[ -d "$dir" ] || die "no userdb source directory: $dir"

# The one file holding the canary's record.
matches=()
for f in "$dir"/*; do
    [ -f "$f" ] || continue
    if awk -F'\t' -v u="$canary" '$1 == u {n++} END {exit !(n > 0)}' "$f"; then
        matches+=("$f")
    fi
done
[ "${#matches[@]}" -eq 1 ] \
    || die "expected exactly one file in $dir with a record for $canary, found ${#matches[@]}"
src=${matches[0]}

# 32 alphanumerics. Captured whole, then cut: piping into head -c would close
# the pipe early and fail under pipefail.
password=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9')
password=${password:0:32}
[ "${#password}" -eq 32 ] || die "could not generate a password"
hash=$(printf '%s\n' "$password" | openssl passwd -6 -stdin)

umask 077
tmp_src=$(mktemp "$dir/.rotate.XXXXXX")
tmp_pw=$(mktemp "$(dirname "$pwfile")/.rotate.XXXXXX")
trap 'rm -f "$tmp_src" "$tmp_pw"' EXIT

# Exit 3: the canary's record has no systempw to replace; 4: more than one record.
status=0
HASH="$hash" awk -F'\t' -v OFS='\t' -v u="$canary" '
    $1 == u {
        if (++seen > 1) exit 4
        n = split($2, f, "|"); replaced = 0
        for (i = 1; i <= n; i++)
            if (f[i] ~ /^systempw=/) { f[i] = "systempw=" ENVIRON["HASH"]; replaced = 1 }
        if (!replaced) exit 3
        s = f[1]; for (i = 2; i <= n; i++) s = s "|" f[i]
        $2 = s
    }
    { print }' "$src" > "$tmp_src" || status=$?
case "$status" in
    0) ;;
    3) die "the record for $canary in $src has no systempw field" ;;
    4) die "$src has more than one record for $canary" ;;
    *) die "rewriting $src failed" ;;
esac

printf '%s\n' "$password" > "$tmp_pw"
chown --reference="$src" "$tmp_src"
chmod --reference="$src" "$tmp_src"
mv -f "$tmp_src" "$src"
mv -f "$tmp_pw" "$pwfile"
trap - EXIT

echo "rotated the password for $canary in $src; written to $pwfile"
