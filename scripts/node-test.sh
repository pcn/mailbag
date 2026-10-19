#!/bin/bash
# Deploy an image tag to this host and test it end to end.
#
#   scripts/node-test.sh sha-<commit>
#
# Run on the host, as root, from a checkout or the deploy tree. Deploys the tag
# with deployment/k8s/deploy-services.sh, then runs each goss suite as its own
# run, in an order that keeps failures diagnosable -- smoke (pods, rollout,
# image tag, ports), certificates (TLS on every port), cert-manager (when
# tls.source is cert-manager), mail delivery (submit on 25/587/465, retrieve
# over IMAPS) -- reports each on its own line, and exits non-zero if any
# failed. Every suite runs even after an earlier one fails.
#
# Environment:
#   CONTEXT               default /etc/mailbag/context.json
#   CANARY_PASSWORD_FILE  default /root/.mailbag-canary-pass; userdb.canary's
#                         password, never printed. Each run that deploys first
#                         gives the canary a fresh random password
#                         (scripts/rotate-canary-password.sh) and writes it
#                         here, so the deploy publishes it and the suites use it.
#   CA_BUNDLE             trust anchor for a private CA (tls.source=secret);
#                         unset means system trust
#   SKIP_DEPLOY=1         test what is deployed now, expecting it to be the tag;
#                         the password is not rotated, since nothing would
#                         publish it, and CANARY_PASSWORD_FILE must already exist
#
# Only smoke and certificates retry, because their state converges on its own
# (the rollout finishing, the certificate Secret reaching the pods' mounts).
# Mail delivery never retries: a retry would submit the messages again; its
# client polls IMAP with a deadline instead.
#
# PROJ-009.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TAG="${1:?usage: $0 IMAGE_TAG   (e.g. sha-<commit>)}"
CONTEXT="${CONTEXT:-/etc/mailbag/context.json}"
CANARY_PASSWORD_FILE="${CANARY_PASSWORD_FILE:-/root/.mailbag-canary-pass}"

die() { echo "node-test: $*" >&2; exit 2; }
[ -r "$CONTEXT" ] || die "context not readable: $CONTEXT"
[ -z "${CA_BUNDLE:-}" ] || [ -r "$CA_BUNDLE" ] || die "CA_BUNDLE not readable: $CA_BUNDLE"
GOSS=$(scripts/fetch-goss.sh "$CONTEXT") || die "could not fetch goss"

if [ "${SKIP_DEPLOY:-}" = 1 ]; then
    [ -r "$CANARY_PASSWORD_FILE" ] || die "canary password file not readable: $CANARY_PASSWORD_FILE"
else
    echo "===== canary password"
    scripts/rotate-canary-password.sh \
        "$(jq -er '.config.authlib_path' "$CONTEXT")/userdb" \
        "$(jq -er '.userdb.canary' "$CONTEXT")" \
        "$CANARY_PASSWORD_FILE" || die "could not rotate the canary password; nothing deployed"
    echo "===== deploy $TAG"
    if ! IMAGE_TAG="$TAG" CONTEXT="$CONTEXT" deployment/k8s/deploy-services.sh; then
        echo "node-test: deploy of $TAG failed; not testing" >&2
        exit 1
    fi
fi

# Extra goss variables, as JSON for --vars-inline.
ca_json=$([ -n "${CA_BUNDLE:-}" ] && jq -nc --arg ca "$CA_BUNDLE" '{ca_bundle: $ca}' || echo '{}')
run_id="$(date -u +%Y%m%dT%H%M%SZ)-${TAG:0:16}"

declare -a NAMES=() RESULTS=()
suite() {  # name inline-vars-json [goss validate flags...]
    local name=$1 inline=$2; shift 2
    echo "===== $name"
    if "$GOSS" -g "goss/$name.yaml" --vars "$CONTEXT" --vars-inline "$inline" \
            validate --format documentation "$@"; then
        RESULTS+=(pass)
    else
        RESULTS+=(FAIL)
    fi
    NAMES+=("$name")
}

suite smoke "$(jq -nc --arg t "$TAG" '{image_tag: $t}')" --retry-timeout 300s --sleep 10s
suite certificates "$ca_json" --retry-timeout 90s --sleep 10s
if [ "$(jq -r '.tls.source' "$CONTEXT")" = cert-manager ]; then
    suite cert-manager '{}'
fi
suite mail-delivery "$(jq -nc --argjson ca "$ca_json" --arg pw "$CANARY_PASSWORD_FILE" --arg run "$run_id" \
    '$ca + {canary_password_file: $pw, run_id: $run}')"

echo "===== node-test $TAG"
status=0
for i in "${!NAMES[@]}"; do
    printf '  %-14s %s\n' "${NAMES[$i]}" "${RESULTS[$i]}"
    [ "${RESULTS[$i]}" = pass ] || status=1
done
exit "$status"
