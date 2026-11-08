#!/bin/bash
# PROJ-031: the pinned renderer (upstream minijinja-cli, invoked as
# `renderer --strict -n TEMPLATE CONTEXT`) keeps the guarantee the in-house
# render-template gave: printing anything undefined is an error, while
# `| default(...)` still works. Run by goss/repo.yaml; offline.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

RENDERER=$(scripts/fetch-renderer.sh examples/example-context.json) || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
printf '%s' '{"a": {"b": "present"}, "items": ["x", "y"]}' > "$work/ctx.json"

fail=0
# name <TAB> template <TAB> expected output, or ! for "must exit non-zero".
# Tab-separated: the templates themselves contain "|".
while IFS=$'\t' read -r name template want; do
    [ -n "$name" ] || continue
    printf '%s' "$template" > "$work/t.j2"
    if out=$("$RENDERER" --strict -n "$work/t.j2" "$work/ctx.json" 2>/dev/null); then
        if [ "$want" = '!' ]; then echo "FAIL  rendered, should have failed: $name"; fail=1
        elif [ "$out" = "$want" ]; then echo "ok    $name"
        else echo "FAIL  $name: got '$out', want '$want'"; fail=1; fi
    else
        if [ "$want" = '!' ]; then echo "ok    fails: $name"
        else echo "FAIL  failed, should have rendered: $name"; fail=1; fi
    fi
done <<EOF
a present value renders	{{ a.b }}	present
printing a missing key fails	{{ a.nope }}	!
printing a missing top-level name fails	{{ nope }}	!
printing through a missing intermediate fails	{{ nope.deeper }}	!
default() fills a missing key	{{ a.nope | default("fallback") }}	fallback
default() does not mask a present value	{{ a.b | default("fallback") }}	present
iterating a present list works	{% for i in items %}{{ i }}{% endfor %}	xy
EOF
exit "$fail"
