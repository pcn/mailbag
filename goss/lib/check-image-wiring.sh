#!/bin/bash
# How the images are wired to their pins. Run by goss/repo.yaml; offline.
#
#   PROJ-032: the base builds FROM the packages image named by this commit's
#   content key, never :main, and the packages job is never skipped by a path
#   filter -- whether it compiles is the key's decision alone.
#   PROJ-031: the renderer is pinned once, in examples/example-context.json;
#   the base job reads the pin from there and Dockerfile-base's build args
#   have no defaults, so a build without them fails.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

WF=.github/workflows/build-and-publish.yml
command -v yq >/dev/null || { echo "FAIL  yq not found"; exit 1; }
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

base_args=$(yq -r '.jobs.base.steps[] | select(.uses == "docker/build-push-action@v6") | .with."build-args"' "$WF")

# --- PROJ-032 ------------------------------------------------------------------
grep -qE '^PACKAGES_IMAGE=.*-packages:\$\{\{ needs\.packages\.outputs\.key \}\}$' <<<"$base_args" \
    && ok "the base's PACKAGES_IMAGE is the packages job's key output" \
    || bad "the base's PACKAGES_IMAGE is not the packages key: $(grep PACKAGES_IMAGE <<<"$base_args")"
grep -q -- '-packages:main' "$WF" && bad "the workflow names mailbag-packages:main" \
    || ok "nothing in the workflow names mailbag-packages:main"
[ "$(yq -r '.jobs.packages.if // ""' "$WF")" = "" ] \
    && ok "the packages job always runs (no if:, so no path filter can skip it)" \
    || bad "the packages job has an if: $(yq -r '.jobs.packages.if' "$WF")"
yq -r '.jobs.base.needs[]' "$WF" | grep -qx packages \
    && ok "the base job needs the packages job" || bad "the base job does not need packages"

# --- PROJ-031 ------------------------------------------------------------------
jq -e '.tools.minijinja_cli.version
       and (.tools.minijinja_cli.sha256 | has("x86_64-unknown-linux-gnu") and has("aarch64-unknown-linux-gnu"))' \
    examples/example-context.json >/dev/null \
    && ok "the example context pins minijinja-cli's version and a sha256 per target" \
    || bad "the example context does not pin minijinja-cli"
reads=$(yq -r '.jobs.base.steps[] | select(.id == "renderer") | .run' "$WF")
if grep -q 'examples/example-context.json' <<<"$reads" && grep -q '.tools.minijinja_cli.version' <<<"$reads"; then
    ok "the base job reads the renderer pin from examples/example-context.json"
else
    bad "the base job does not read the renderer pin from the example context"
fi
for arg in MINIJINJA_CLI_VERSION MINIJINJA_CLI_SHA256_X86_64 MINIJINJA_CLI_SHA256_AARCH64; do
    grep -qE "^$arg=\\\$\{\{ steps\.renderer\.outputs\." <<<"$base_args" \
        || bad "the base build does not pass $arg from the renderer step"
    if grep -qE "^ARG $arg=" Dockerfile-base; then
        bad "Dockerfile-base gives $arg a default"
    elif grep -qE "^ARG $arg$" Dockerfile-base; then
        ok "Dockerfile-base declares $arg with no default, passed from the pin"
    else
        bad "Dockerfile-base does not declare $arg"
    fi
done

exit "$fail"
