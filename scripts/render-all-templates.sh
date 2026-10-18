#!/bin/bash
# Render every template in the repo against its context and fail if any of them
# references a key the context does not provide.
#
# The renderer runs with --strict, which treats printing an undefined value as
# an error, so this catches the case where a template references a context key
# that was never added -- which would otherwise render as an empty string with
# a zero exit code and produce silently broken courier config.
#
# Every template renders against the example context. Keep the table below in
# sync when templates are added. The courier config templates carried as data
# in configmap.yaml are rendered too, because the entrypoints render them with
# the same renderer at container start.

set -u -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONTEXT="${CONTEXT:-examples/example-context.json}"

# The renderer and its version come from the example context, the same pin the
# images are built with.
RENDERER=$(scripts/fetch-renderer.sh examples/example-context.json) || exit 1

# template path : context path
TEMPLATES=(
    "deployment/k8s/prepare-host.sh.template:$CONTEXT"
    "deployment/k8s/mail-certificates.yaml.template:$CONTEXT"
    "deployment/k8s/courierd.yaml.template:$CONTEXT"
    "deployment/k8s/courier-mta.yaml.template:$CONTEXT"
    "deployment/k8s/courier-mta-ssl.yaml.template:$CONTEXT"
    "deployment/k8s/courier-imapd-ssl.yaml.template:$CONTEXT"
    "deployment/k8s/courier-msa.yaml.template:$CONTEXT"
    "deployment/k8s/build-dat-job.yaml.template:$CONTEXT"
)

# Fail if a template exists that the table does not cover, so new templates
# cannot quietly escape the check.
mapfile -t FOUND < <(
    find . -name '*.template' \
        -not -path './.git/*' \
        -printf '%P\n' | sort
)
declare -A LISTED=()
for entry in "${TEMPLATES[@]}"; do
    LISTED["${entry%%:*}"]=1
done

status=0

for t in "${FOUND[@]}"; do
    if [ -z "${LISTED[$t]:-}" ]; then
        echo "UNCOVERED  $t is not listed in scripts/render-all-templates.sh"
        status=1
    fi
done

for entry in "${TEMPLATES[@]}"; do
    template="${entry%%:*}"
    context="${entry##*:}"

    if [ ! -f "$template" ]; then
        printf 'MISSING    %-46s (listed but not on disk)\n' "$template"
        status=1
        continue
    fi

    if out=$("$RENDERER" --strict -n "$template" "$context" 2>&1); then
        printf 'ok         %-46s (%s)\n' "$template" "$context"
    else
        printf 'FAIL       %-46s (%s)\n' "$template" "$context"
        printf '%s\n' "$out" | sed 's/^/               /'
        status=1
    fi
done

CM_WORK=$(mktemp -d); trap 'rm -rf "$CM_WORK"' EXIT
python3 -I - deployment/k8s/configmap.yaml "$CM_WORK" <<'PYEOF'
import pathlib, sys, yaml
out = pathlib.Path(sys.argv[2])
for doc in yaml.safe_load_all(pathlib.Path(sys.argv[1]).read_text()):
    for name, body in ((doc or {}).get("data") or {}).items():
        if name.endswith(".template"):
            (out / name).write_text(body)
PYEOF
for template in "$CM_WORK"/*.template; do
    label="configmap.yaml:$(basename "$template")"
    if out=$("$RENDERER" --strict -n "$template" "$CONTEXT" 2>&1); then
        printf 'ok         %-46s (%s)\n' "$label" "$CONTEXT"
    else
        printf 'FAIL       %-46s (%s)\n' "$label" "$CONTEXT"
        printf '%s\n' "$out" | sed 's/^/               /'
        status=1
    fi
done

if [ "$status" -ne 0 ]; then
    echo
    echo "One or more templates reference context keys that are not provided."
    echo "Either add the key to $CONTEXT and generate-context.sh, or make the"
    echo 'reference explicitly optional with `| default("...")`.'
fi

exit "$status"
