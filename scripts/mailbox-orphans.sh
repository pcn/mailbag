#!/bin/bash
# List maildirs that belong to no declared mailbox, or the archived ones.
#
#   scripts/mailbox-orphans.sh [CONTEXT]              (default /etc/mailbag/context.json)
#   scripts/mailbox-orphans.sh --archived [CONTEXT]
#
# Removing a mailbox from the context removes its login but keeps its mail
# (PROJ-040); its maildir is then an orphan. This prints one address per
# orphan, nothing when there are none, and always exits 0: an orphan is
# information, never a failure, and nothing here deletes anything.
# With --archived it prints instead the maildirs scripts/mailbox-archive.sh
# has moved under host_paths.mail_archive, one <domain>/<user>-<timestamp>
# per line (PROJ-042); those are not orphans and never appear in the default
# report. scripts/node-test.sh reports both; PROJ-041 replaces this with a
# service metric.

set -u -o pipefail

archived=""
if [ "${1:-}" = --archived ]; then archived=1; shift; fi
CONTEXT="${1:-/etc/mailbag/context.json}"

if [ -n "$archived" ]; then
    archive=$(jq -er '.host_paths.mail_archive' "$CONTEXT") || exit 0
    for d in "${archive%/}"/*/*; do
        [ -d "$d" ] || continue
        echo "$(basename "$(dirname "$d")")/$(basename "$d")"
    done
    exit 0
fi

mail=$(jq -er '.host_paths.mail' "$CONTEXT") || exit 0
declared=$(jq -r '.mailboxes[]' "$CONTEXT")

for maildir in "$mail"/*/*/Maildir; do
    [ -d "$maildir" ] || continue
    user_dir=${maildir%/Maildir}
    address="$(basename "$user_dir")@$(basename "$(dirname "$user_dir")")"
    printf '%s\n' "$declared" | grep -qxF "$address" || echo "$address"
done
exit 0
