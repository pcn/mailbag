#!/bin/bash
# Check that generate-context.sh writes a context that satisfies
# cue/schema.cue's #Context. Run by goss/repo.yaml.
#
# Runs the real script, answering every prompt with Enter (its defaults) and
# writing to a scratch path via CONTEXT_OUT, once for each certificate source,
# since tls is built differently for each.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

CUE=$(scripts/fetch-cue.sh examples/example-context.json) || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
printf '\n%.0s' $(seq 20) > "$work/answers"

fail=0
for source in cert-manager secret; do
    out="$work/context-$source.json"
    # Empty answers from a file, not `yes |`: yes dies of SIGPIPE when the
    # script exits, which pipefail would report as the script failing.
    if ! CONTEXT_OUT="$out" TLS_SOURCE="$source" ACME_HOSTED_ZONE_ID=Z0000000000000EXAMPLE \
            ./generate-context.sh <"$work/answers" >"$work/log" 2>&1; then
        echo "FAIL  generate-context.sh (TLS_SOURCE=$source) exited non-zero:"; sed 's/^/        /' "$work/log"
        fail=1
        continue
    fi
    if "$CUE" vet -c -d '#Context' ./cue "$out" > "$work/err" 2>&1; then
        echo "ok    generate-context.sh (TLS_SOURCE=$source) writes a context the schema accepts"
    else
        echo "FAIL  generate-context.sh (TLS_SOURCE=$source) writes a context the schema rejects:"; sed 's/^/        /' "$work/err"
        fail=1
    fi
done

# The hosted zone id cannot be guessed, so cert-manager without one must stop
# before writing anything.
out="$work/context-no-zone-id.json"
if CONTEXT_OUT="$out" TLS_SOURCE=cert-manager ./generate-context.sh <"$work/answers" >"$work/log" 2>&1; then
    echo "FAIL  generate-context.sh (TLS_SOURCE=cert-manager, no ACME_HOSTED_ZONE_ID) succeeded"
    fail=1
elif [ -e "$out" ]; then
    echo "FAIL  generate-context.sh (no ACME_HOSTED_ZONE_ID) failed but still wrote $out"
    fail=1
else
    echo "ok    generate-context.sh refuses cert-manager without ACME_HOSTED_ZONE_ID"
fi
exit "$fail"
