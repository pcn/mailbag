#!/bin/bash
# Render every template in the repo against its context and fail if any of them
# references a key the context does not provide.
#
# render-template treats printing an undefined value as an error, so this
# catches the case where a template references a context key that was never
# added -- which previously rendered as an empty string with a zero exit code
# and produced silently broken courier config.
#
# Templates do not all share one context: unit-files/Makefile.template is
# rendered against unit-files/files.json, everything else against the example
# context. Keep the table below in sync when templates are added.

set -u -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONTEXT="${CONTEXT:-examples/example-context.json}"

# Build from source rather than trusting the committed render-template binary,
# which is a stale artifact (see PROJ-014).
RENDERER="templater/target/debug/render-template"
if [ ! -x "$RENDERER" ] || [ "templater/src/main.rs" -nt "$RENDERER" ]; then
    echo "building $RENDERER ..."
    (cd templater && cargo build --quiet) || exit 1
fi

# template path : context path
TEMPLATES=(
    "acceptmailfor.template:$CONTEXT"
    "hosteddomains.template:$CONTEXT"
    "host/Makefile.template:$CONTEXT"
    "deployment/k8s/prepare-host.sh.template:$CONTEXT"
    "deployment/k8s/mail-certificates.yaml.template:$CONTEXT"
    "deployment/k8s/courierd.yaml.template:$CONTEXT"
    "deployment/k8s/courier-mta.yaml.template:$CONTEXT"
    "deployment/k8s/courier-mta-ssl.yaml.template:$CONTEXT"
    "deployment/k8s/courier-imapd-ssl.yaml.template:$CONTEXT"
    "deployment/k8s/courier-msa.yaml.template:$CONTEXT"
    "unit-files/Makefile.template:unit-files/files.json"
)

# Fail if a template exists that the table does not cover, so new templates
# cannot quietly escape the check.
mapfile -t FOUND < <(
    find . -name '*.template' \
        -not -path './.git/*' \
        -not -path './templater/target/*' \
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

    if out=$("$RENDERER" --context "$context" --template "$template" 2>&1); then
        printf 'ok         %-46s (%s)\n' "$template" "$context"
    else
        printf 'FAIL       %-46s (%s)\n' "$template" "$context"
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
