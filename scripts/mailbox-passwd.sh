#!/bin/bash
# Set a mailbox's password hash in the passwords file.
#
#   scripts/mailbox-passwd.sh ADDRESS                 prompt (twice, no echo)
#   scripts/mailbox-passwd.sh --random FILE ADDRESS   random, written to FILE (0600)
#   scripts/mailbox-passwd.sh --random - ADDRESS      random, not kept: a
#                                                     receive-only mailbox
#
# PASSWORDS (default /etc/mailbag/passwords) holds address:hash lines, root
# only. Only ADDRESS's line changes -- replaced, or added -- and the file is
# swapped in atomically, keeping its owner and mode (0600 if new). The hash is
# SHA-512 crypt (openssl passwd -6; userdbpw is not on the node). The next
# deploy's database build job generates the userdb from the context's
# mailboxes and these hashes; ADDRESS must also be a declared mailbox, or that
# build refuses the stray hash.
#
# The password is never printed and never on a command line: it reaches
# openssl on stdin. PROJ-040.

set -e -u -o pipefail

PASSWORDS="${PASSWORDS:-/etc/mailbag/passwords}"
die() { echo "mailbox-passwd: $*" >&2; exit 1; }

random=""
if [ "${1:-}" = --random ]; then
    random=${2:?usage: $0 [--random FILE|-] ADDRESS}
    shift 2
fi
address="${1:?usage: $0 [--random FILE|-] ADDRESS}"
[[ "$address" =~ ^[a-z0-9][a-z0-9._+-]*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] \
    || die "not a lowercase address: $address"

if [ -n "$random" ]; then
    # 32 alphanumerics. Captured whole, then cut: piping into head -c would
    # close the pipe early and fail under pipefail.
    password=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9')
    password=${password:0:32}
    [ "${#password}" -eq 32 ] || die "could not generate a password"
else
    [ -t 0 ] || die "no terminal to prompt on; use --random"
    read -r -s -p "Password for $address: " password; echo >&2
    read -r -s -p "Again: " again; echo >&2
    [ "$password" = "$again" ] || die "the passwords differ"
    [ -n "$password" ] || die "empty password"
fi
hash=$(printf '%s\n' "$password" | openssl passwd -6 -stdin)

umask 077
dir=$(dirname "$PASSWORDS")
tmp=$(mktemp "$dir/.passwords.XXXXXX")
tmp_pw=""
trap 'rm -f "$tmp" ${tmp_pw:+"$tmp_pw"}' EXIT

# Every line but ADDRESS's, then ADDRESS's new one. The hash reaches awk
# through the environment.
if [ -e "$PASSWORDS" ]; then
    awk -v a="$address" 'index($0, a ":") != 1' "$PASSWORDS" > "$tmp"
    chown --reference="$PASSWORDS" "$tmp"
    chmod --reference="$PASSWORDS" "$tmp"
fi
HASH="$hash" awk -v a="$address" 'BEGIN { print a ":" ENVIRON["HASH"] }' >> "$tmp"

if [ -n "$random" ] && [ "$random" != - ]; then
    tmp_pw=$(mktemp "$(dirname "$random")/.mailbox-passwd.XXXXXX")
    printf '%s\n' "$password" > "$tmp_pw"
fi
mv -f "$tmp" "$PASSWORDS"
[ -z "$tmp_pw" ] || mv -f "$tmp_pw" "$random"
trap - EXIT

case "$random" in
    "") echo "set the password for $address in $PASSWORDS" ;;
    -)  echo "set a random password for $address in $PASSWORDS (not kept)" ;;
    *)  echo "set a random password for $address in $PASSWORDS; written to $random" ;;
esac
