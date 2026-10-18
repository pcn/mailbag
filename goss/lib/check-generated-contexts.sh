#!/bin/bash
# Check that each generate-context.sh writes a context that satisfies
# cue/schema.cue's #Context. Run by goss/repo.yaml.
#
# The generators are interactive and write to /etc/mailbag, so instead of
# running them this renders each one's JSON heredoc with its own defaults. The
# tool pins are copied in from the example, exactly as the generators do after
# writing.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

EXAMPLE=examples/example-context.json
CUE=$(scripts/fetch-cue.sh "$EXAMPLE") || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

render() { # generator -> its default context on stdout
    local g=$1
    {
        # Defaults: every line before the first prompt, minus set -e.
        awk '/^read -p/{exit} {print}' "$g" | grep -v '^set -e'
        # The root generator turns prefixes into FQDNs after the prompts.
        echo 'MAIL_HOSTNAME="$MAIL_HOSTNAME.$DOMAIN"; IMAP_HOSTNAME="$IMAP_HOSTNAME.$DOMAIN"; SMTP_HOSTNAME="$SMTP_HOSTNAME.$DOMAIN"'
        echo 'cat <<EOF'
        awk '/<< EOF$/{f=1;next} /^EOF$/{f=0} f' "$g"
        echo 'EOF'
    } > "$work/render.sh"
    bash "$work/render.sh"
}

fail=0
for g in generate-context.sh deployment/k8s/generate-context.sh; do
    if ! render "$g" | jq --slurpfile ex "$EXAMPLE" '.tools = $ex[0].tools' > "$work/ctx.json" 2>"$work/err"; then
        echo "FAIL  $g does not produce valid JSON:"; sed 's/^/        /' "$work/err"
        fail=1
        continue
    fi
    if "$CUE" vet -c -d '#Context' ./cue "$work/ctx.json" > "$work/err" 2>&1; then
        echo "ok    $g writes a context that satisfies the schema"
    else
        echo "FAIL  $g writes a context the schema rejects:"; sed 's/^/        /' "$work/err"
        fail=1
    fi
done
exit "$fail"
