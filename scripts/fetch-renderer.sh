#!/bin/bash
# Print the path of the template renderer pinned by a context.json, fetching
# and verifying it first if it is not already cached.
#
#   RENDERER=$(scripts/fetch-renderer.sh /etc/mailbag/context.json)
#   "$RENDERER" --strict -n TEMPLATE CONTEXT > OUTPUT
#
# The renderer is upstream minijinja-cli, installed under the name `renderer`.
# Its version and per-target sha256 come from .tools.minijinja_cli in the
# context, so the context is the only place the version is pinned; the images
# take the same values from examples/example-context.json at build time.
#
# --strict makes printing an undefined value an error, so a template that
# references a key the context does not provide fails instead of rendering an
# empty string. `| default(...)` on a missing key still works. -n keeps the
# output byte-identical to the renderer this replaced, which did not add a
# trailing newline.

set -e -u -o pipefail

CONTEXT="${1:?usage: $0 CONTEXT_JSON}"
CACHE="${MAILBAG_TOOL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mailbag}"

die() { echo "fetch-renderer: $*" >&2; exit 1; }

[ -r "$CONTEXT" ] || die "context not readable: $CONTEXT"
for tool in curl jq sha256sum tar xz; do
    command -v "$tool" >/dev/null || die "$tool not found"
done

case "$(uname -m)" in
    x86_64)  target=x86_64-unknown-linux-gnu ;;
    aarch64) target=aarch64-unknown-linux-gnu ;;
    *)       die "no minijinja-cli target for $(uname -m)" ;;
esac

version=$(jq -er '.tools.minijinja_cli.version' "$CONTEXT") \
    || die "$CONTEXT has no .tools.minijinja_cli.version"
sha256=$(jq -er --arg t "$target" '.tools.minijinja_cli.sha256[$t]' "$CONTEXT") \
    || die "$CONTEXT has no .tools.minijinja_cli.sha256 for $target"

dir="$CACHE/minijinja-cli-$version-$target"
bin="$dir/renderer"

if [ ! -x "$bin" ]; then
    tarball="minijinja-cli-$target.tar.xz"
    url="https://github.com/mitsuhiko/minijinja/releases/download/$version/$tarball"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/$tarball" "$url" || die "download failed: $url"
    echo "$sha256  $tmp/$tarball" | sha256sum -c --quiet - \
        || die "sha256 mismatch for $url"
    tar -xJf "$tmp/$tarball" -C "$tmp"
    mkdir -p "$dir"
    # Private name, then an atomic rename, so a concurrent caller never runs a
    # half-written binary (see fetch-cue.sh).
    install -m 0755 "$tmp/minijinja-cli-$target/minijinja-cli" "$bin.$$"
    mv -f "$bin.$$" "$bin"
fi

# A cached binary is trusted only if it still reports the pinned version.
# Captured, not piped, so an early-exiting reader can never SIGPIPE the binary.
reported=$("$bin" --version) || die "$bin --version failed"
[ "${reported%%$'\n'*}" = "minijinja-cli $version" ] \
    || die "$bin does not report minijinja-cli $version"

echo "$bin"