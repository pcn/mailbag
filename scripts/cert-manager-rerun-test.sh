#!/bin/bash
# Show that re-running host setup at the deployed cert-manager version changes
# nothing (PROJ-027).
#
#   scripts/cert-manager-rerun-test.sh
#
# Run on the host, as root, from the deploy tree or a checkout, once
# cert-manager is installed at the version host.cert_manager pins. Records the
# generation of each cert-manager deployment, runs host setup's apply, then
# runs goss/cert-manager.yaml with those generations as
# cert_manager_generations: every check there must pass, and each deployment's
# generation must be the one recorded before the re-run. Exits non-zero if
# apply or any check fails.
#
# Environment: CONTEXT (default /etc/mailbag/context.json).

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONTEXT="${CONTEXT:-/etc/mailbag/context.json}"
die() { echo "cert-manager-rerun-test: $*" >&2; exit 2; }
[ -r "$CONTEXT" ] || die "context not readable: $CONTEXT"
[ "$(jq -r '.tls.source' "$CONTEXT")" = cert-manager ] \
    || die "tls.source is not cert-manager in $CONTEXT; host setup does not install it"

DEPLOYMENTS=(cert-manager cert-manager-cainjector cert-manager-webhook)
generations() {
    kubectl -n cert-manager get deploy "${DEPLOYMENTS[@]}" -o json \
        | jq -ce '[.items[] | {(.metadata.name): .metadata.generation}] | add'
}

before=$(generations) || die "could not read the cert-manager deployments; is it installed?"
echo "===== generations before: $before"

CUE=$(scripts/fetch-cue.sh "$CONTEXT") || die "could not fetch cue"
echo "===== host setup apply"
"$CUE" cmd -t ctx="$(cat "$CONTEXT")" apply ./cue || die "host setup apply failed"

echo "===== goss/cert-manager.yaml with the generations from before"
GOSS=$(scripts/fetch-goss.sh "$CONTEXT") || die "could not fetch goss"
"$GOSS" -g goss/cert-manager.yaml --vars "$CONTEXT" \
    --vars-inline "$(jq -nc --argjson g "$before" '{cert_manager_generations: $g}')" \
    validate --format documentation
