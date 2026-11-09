#!/bin/bash
# PROJ-042: scripts/mailbox-archive.sh moves an orphaned maildir aside and
# back intact, and refuses -- moving and deleting nothing -- a declared
# mailbox, an existing target, an archive on another filesystem, and a
# restore onto an existing maildir. Run by goss/repo.yaml.
#
# Fixtures live in a temp directory; the cross-filesystem case puts the
# archive on a second filesystem (/dev/shm, or another candidate below) and
# fails the check if none is available, rather than skipping it.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
ARCHIVE_SH=$PWD/scripts/mailbox-archive.sh
ORPHANS_SH=$PWD/scripts/mailbox-orphans.sh

work=$(mktemp -d) other=""
trap 'rm -rf "$work" ${other:+"$other"}' EXIT
for c in /dev/shm "${XDG_RUNTIME_DIR:-}" /run/user/"$(id -u)" /var/tmp "$HOME"; do
    [ -n "$c" ] && [ -d "$c" ] && [ -w "$c" ] || continue
    [ "$(stat -c %d "$c")" != "$(stat -c %d "$work")" ] || continue
    other=$(mktemp -d -p "$c") && break
done

D=the-domain.com
mail=$work/mail archive=$work/archive

# A context whose mailboxes include kept@ but not gone@.
context() {  # file mail archive
    jq --arg m "$2" --arg a "$3" \
        '.host_paths.mail = $m | .host_paths.mail_archive = $a | .mailboxes += ["kept@the-domain.com"]' \
        examples/example-context.json > "$1"
}
context "$work/context.json" "$mail" "$archive"
export CONTEXT=$work/context.json

# A maildir with messages in the inbox and a folder, and varied modes.
mkmaildir() {
    local u=$1
    mkdir -p "$u/Maildir/cur" "$u/Maildir/new" "$u/Maildir/tmp" "$u/Maildir/.Sent/cur" "$u/Maildir/.Sent/new"
    echo "one"   > "$u/Maildir/cur/1.host:2,S"
    echo "two"   > "$u/Maildir/new/2.host"
    echo "three" > "$u/Maildir/.Sent/cur/3.host:2,S"
    echo "sub"   > "$u/Maildir/courierimapsubscribed"
    chmod 0600 "$u/Maildir/cur/1.host:2,S" "$u/Maildir/new/2.host"
    chmod 0640 "$u/Maildir/.Sent/cur/3.host:2,S"
    chmod 0700 "$u/Maildir" "$u/Maildir/cur" "$u/Maildir/new" "$u/Maildir/tmp"
    chmod 0750 "$u/Maildir/.Sent"
}
mkmaildir "$mail/$D/gone"
mkmaildir "$mail/$D/kept"

# Every entry under DIR: relative path, type, owner, group, mode, and a
# content hash for files.
snapshot() {
    (cd "$1" && find . -printf '%P %y %U %G %m\n' | sort
     find . -type f -print0 | sort -z | xargs -0 -r sha256sum)
}
# Everything under the mail root and the archive (and the other filesystem).
world() {
    for d in "$work/mail" "$work/archive" ${other:+"$other"}; do
        echo "== $d"; [ -e "$d" ] && snapshot "$d"
    done
}

fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

# expect_refusal NAME CMD...: CMD exits non-zero and nothing anywhere changes.
expect_refusal() {
    local name=$1; shift
    local before after
    before=$(world)
    if "$@" > "$work/out" 2>&1; then
        bad "$name: accepted"; sed 's/^/        /' "$work/out"
        return
    fi
    after=$(world)
    if [ "$before" = "$after" ]; then
        ok "$name: refused, nothing moved ($(head -1 "$work/out"))"
    else
        bad "$name: refused but the trees changed:"
        diff <(echo "$before") <(echo "$after") | sed 's/^/        /'
    fi
}

# --- archive an orphan
gone_before=$(snapshot "$mail/$D/gone")
if out=$("$ARCHIVE_SH" gone@$D 2>&1); then
    shopt -s nullglob; moved=("$archive/$D"/gone-*); shopt -u nullglob
    if [ ${#moved[@]} -eq 1 ] && [[ "$(basename "${moved[0]}")" =~ ^gone-[0-9]{8}T[0-9]{6}Z$ ]] \
            && [ ! -e "$mail/$D/gone" ] && [ "$(snapshot "${moved[0]}")" = "$gone_before" ]; then
        ok "an orphan moves intact to <archive>/<domain>/<user>-<timestamp> ($out)"
    else
        bad "archive of gone@$D did not move it intact: $out"
    fi
    case "$out" in *"3 message(s)"*) ok "the message count covers the inbox and folders" ;;
                   *) bad "wrong message count: $out" ;; esac
    if [ "$(stat -c %a "$archive")" = 700 ] && [ "$(stat -c %a "$archive/$D")" = 700 ]; then
        ok "the archive root and domain directory are created 0700"
    else
        bad "archive directories are not 0700"
    fi
    if [ -z "$("$ORPHANS_SH" "$CONTEXT")" ] \
            && [ "$("$ORPHANS_SH" --archived "$CONTEXT")" = "$D/$(basename "${moved[0]}")" ]; then
        ok "the orphan report no longer lists it; --archived does"
    else
        bad "orphan report after archiving: '$("$ORPHANS_SH" "$CONTEXT")' / '$("$ORPHANS_SH" --archived "$CONTEXT")'"
    fi
else
    bad "archive of an orphan failed: $out"
    moved=()
fi

# --- refusals while archiving
expect_refusal "a declared mailbox" "$ARCHIVE_SH" kept@$D
expect_refusal "an address with no maildir" "$ARCHIVE_SH" nobody@$D

mkmaildir "$mail/$D/again"
mkdir -p "$work/bin" "$archive/$D/again-20260101T000000Z"
printf '#!/bin/sh\necho 20260101T000000Z\n' > "$work/bin/date"; chmod +x "$work/bin/date"
expect_refusal "an existing target" env PATH="$work/bin:$PATH" "$ARCHIVE_SH" again@$D

if [ -n "$other" ]; then
    context "$work/context-xdev.json" "$mail" "$other/archive"
    expect_refusal "an archive on a different filesystem" \
        env CONTEXT="$work/context-xdev.json" "$ARCHIVE_SH" again@$D
    [ ! -e "$other/archive" ] && ok "the cross-filesystem refusal created nothing" \
        || bad "the cross-filesystem refusal created $other/archive"
else
    bad "no second filesystem to test the cross-filesystem refusal"
fi

# --- restore
if [ ${#moved[@]} -eq 1 ]; then
    if out=$("$ARCHIVE_SH" --restore "${moved[0]}" 2>&1) \
            && [ ! -e "${moved[0]}" ] && [ "$(snapshot "$mail/$D/gone")" = "$gone_before" ]; then
        ok "--restore moves an archived maildir back intact ($(head -1 <<<"$out"))"
    else
        bad "--restore did not move it back intact: $out"
    fi
    # Archive it again, then let a maildir reappear (as a re-declared
    # mailbox's init container would make one) and try to restore over it.
    if out=$(env PATH="$work/bin:$PATH" "$ARCHIVE_SH" gone@$D 2>&1); then
        mkmaildir "$mail/$D/gone"
        expect_refusal "--restore onto an existing maildir" \
            "$ARCHIVE_SH" --restore "$archive/$D/gone-20260101T000000Z"
    else
        bad "re-archive for the restore refusal failed: $out"
    fi
fi
expect_refusal "--restore of a directory outside the archive" "$ARCHIVE_SH" --restore "$mail/$D/kept"

exit $fail
