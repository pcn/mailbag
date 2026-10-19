#!/bin/bash
# List maildirs that belong to no declared mailbox.
#
#   scripts/mailbox-orphans.sh [CONTEXT]     (default /etc/mailbag/context.json)
#
# Removing a mailbox from the context removes its login but keeps its mail
# (PROJ-040); its maildir is then an orphan. This prints one address per
# orphan, nothing when there are none, and always exits 0: an orphan is
# information, never a failure, and nothing here deletes anything.
# scripts/node-test.sh reports it; PROJ-041 replaces it with a service metric.

set -u -o pipefail

CONTEXT="${1:-/etc/mailbag/context.json}"
mail=$(jq -er '.host_paths.mail' "$CONTEXT") || exit 0
declared=$(jq -r '.mailboxes[]' "$CONTEXT")

for maildir in "$mail"/*/*/Maildir; do
    [ -d "$maildir" ] || continue
    user_dir=${maildir%/Maildir}
    address="$(basename "$user_dir")@$(basename "$(dirname "$user_dir")")"
    printf '%s\n' "$declared" | grep -qxF "$address" || echo "$address"
done
exit 0
