#!/bin/bash
# Put an orphaned maildir away, or bring one back. Nothing here deletes mail.
#
#   scripts/mailbox-archive.sh ADDRESS            archive ADDRESS's maildir
#   scripts/mailbox-archive.sh --restore DIR      move an archived maildir back
#
# Removing a mailbox from the context removes its login and keeps its mail in
# place as an orphan (PROJ-040, scripts/mailbox-orphans.sh). Archiving moves
# <mail>/<domain>/<user> to <mail_archive>/<domain>/<user>-<UTC timestamp>,
# outside the mail root, where courier, IMAP and the orphan report never see
# it. --restore moves it back to <mail>/<domain>/<user>; declare the mailbox
# again (and set its password) to read it.
#
# Each move is one rename(2) -- renameat2 with RENAME_NOREPLACE -- so it is
# instant and all-or-nothing, keeps every owner and mode, and the kernel
# itself refuses to replace an existing target or to cross filesystems. It is
# never a copy: a copy-then-delete across filesystems is where mail gets lost.
# Refusals happen before anything is created or moved:
#   - ADDRESS is still a declared mailbox (only orphans move)
#   - there is no maildir to move
#   - the target already exists
#   - mail_archive is on a different filesystem from mail
#   - (--restore) DIR is not an archived maildir under mail_archive, or the
#     mail root has no directory for its domain
#
# Run by hand, never by a deploy: an automatic move would let a typo in
# `mailboxes` whisk a live mailbox away. Prints how many messages moved.
#
# CONTEXT (default /etc/mailbag/context.json) gives host_paths.mail,
# host_paths.mail_archive and mailboxes. The archive root and its domain
# directories are created 0700 as needed. PROJ-042.

set -e -u -o pipefail

CONTEXT="${CONTEXT:-/etc/mailbag/context.json}"
die() { echo "mailbox-archive: $*" >&2; exit 1; }

USAGE="usage: $0 ADDRESS | --restore DIR"
restore=""
if [ "${1:-}" = --restore ]; then restore=1; shift; fi
arg="${1:?$USAGE}"
[ $# -eq 1 ] || die "$USAGE"

[ -r "$CONTEXT" ] || die "context not readable: $CONTEXT"
mail=$(jq -er '.host_paths.mail' "$CONTEXT") || die "no host_paths.mail in $CONTEXT"
archive=$(jq -er '.host_paths.mail_archive' "$CONTEXT") || die "no host_paths.mail_archive in $CONTEXT"
mail=${mail%/} archive=${archive%/}
[ -d "$mail" ] || die "mail root does not exist: $mail"

# The device of PATH, or of its nearest existing ancestor: a directory created
# there lands on that filesystem.
device() {
    local p=$1
    until [ -e "$p" ]; do p=$(dirname "$p"); done
    stat -c %d "$p"
}

same_filesystem() {
    [ "$(device "$archive")" = "$(device "$mail")" ] \
        || die "$archive and $mail are on different filesystems; an archive must be one rename, never a copy"
}

# Messages in a maildir and all its folders.
count() { find "$1" -type f \( -path '*/cur/*' -o -path '*/new/*' \) | wc -l; }

# rename(2) that never replaces and never copies.
move() {
    python3 -I - "$1" "$2" <<'PY'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
AT_FDCWD, RENAME_NOREPLACE = -100, 1
src, dst = (os.fsencode(a) for a in sys.argv[1:3])
if libc.renameat2(AT_FDCWD, src, AT_FDCWD, dst, RENAME_NOREPLACE) != 0:
    e = ctypes.get_errno()
    sys.exit(f"mailbox-archive: rename {sys.argv[1]} -> {sys.argv[2]}: {os.strerror(e)}")
PY
}

if [ -z "$restore" ]; then
    address=$arg
    [[ "$address" =~ ^[a-z0-9][a-z0-9._+-]*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] \
        || die "not a lowercase address: $address"
    user=${address%@*} domain=${address#*@}
    if jq -e --arg a "$address" '.mailboxes | index($a)' "$CONTEXT" >/dev/null; then
        die "$address is a declared mailbox; only an orphan is archived (remove it from mailboxes and deploy first)"
    fi
    src="$mail/$domain/$user"
    [ -d "$src" ] && [ ! -L "$src" ] || die "no maildir for $address at $src"
    same_filesystem
    dst="$archive/$domain/$user-$(date -u +%Y%m%dT%H%M%SZ)"
    [ ! -e "$dst" ] && [ ! -L "$dst" ] || die "target exists: $dst"
    n=$(count "$src")
    [ -d "$archive" ] || mkdir -m 0700 "$archive"
    [ -d "$archive/$domain" ] || mkdir -m 0700 "$archive/$domain"
    move "$src" "$dst"
    echo "archived $address: $n message(s) moved to $dst"
else
    src=${arg%/}
    domain_dir=$(dirname "$src") base=$(basename "$src")
    domain=$(basename "$domain_dir")
    [ "$(realpath -m "$(dirname "$domain_dir")")" = "$(realpath -m "$archive")" ] \
        || die "not under $archive/<domain>/: $src"
    [[ "$base" =~ ^(.+)-[0-9]{8}T[0-9]{6}Z$ ]] \
        || die "not an archived maildir name (<user>-<UTC timestamp>): $base"
    user=${BASH_REMATCH[1]}
    [ -d "$src" ] && [ ! -L "$src" ] || die "no archived maildir at $src"
    [ -d "$mail/$domain" ] || die "no $mail/$domain; declare a mailbox in $domain and deploy first"
    dst="$mail/$domain/$user"
    [ ! -e "$dst" ] && [ ! -L "$dst" ] || die "$user@$domain already has a maildir at $dst"
    same_filesystem
    n=$(count "$src")
    move "$src" "$dst"
    echo "restored $user@$domain: $n message(s) moved to $dst"
    echo "declare $user@$domain in mailboxes again (and set its password) and deploy to read it"
fi
