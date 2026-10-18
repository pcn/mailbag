#!/bin/bash
# Print the path of the goss binary pinned by a context.json, fetching and
# verifying it first if it is not already cached.
#
#   GOSS=$(scripts/fetch-goss.sh examples/example-context.json)
#   "$GOSS" -g goss/repo.yaml validate
#
# The version and per-target sha256 come from .tools.goss in the context, the
# same way scripts/fetch-renderer.sh pins the template renderer, so the context
# is the only place the version is recorded.

set -e -u -o pipefail

CONTEXT="${1:?usage: $0 CONTEXT_JSON}"
CACHE="${MAILBAG_TOOL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mailbag}"

die() { echo "fetch-goss: $*" >&2; exit 1; }

[ -r "$CONTEXT" ] || die "context not readable: $CONTEXT"
for tool in curl jq sha256sum tar; do
    command -v "$tool" >/dev/null || die "$tool not found"
done

case "$(uname -m)" in
    x86_64)  target=x86_64-unknown-linux-gnu;  asset_arch=x86_64 ;;
    aarch64) target=aarch64-unknown-linux-gnu; asset_arch=arm64 ;;
    *)       die "no goss build for $(uname -m)" ;;
esac

version=$(jq -er '.tools.goss.version' "$CONTEXT") \
    || die "$CONTEXT has no .tools.goss.version"
sha256=$(jq -er --arg t "$target" '.tools.goss.sha256[$t]' "$CONTEXT") \
    || die "$CONTEXT has no .tools.goss.sha256 for $target"

dir="$CACHE/goss-$version-$target"
bin="$dir/goss"

if [ ! -x "$bin" ]; then
    tarball="goss_${version}_linux_${asset_arch}.tar.gz"
    url="https://github.com/goss-org/goss/releases/download/v$version/$tarball"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/$tarball" "$url" || die "download failed: $url"
    echo "$sha256  $tmp/$tarball" | sha256sum -c --quiet - \
        || die "sha256 mismatch for $url"
    tar -xzf "$tmp/$tarball" -C "$tmp"
    found=$(find "$tmp" -type f -name goss | head -1)
    [ -n "$found" ] || die "no goss binary in $tarball"
    mkdir -p "$dir"
    install -m 0755 "$found" "$bin"
fi

# A cached binary is trusted only if it still reports the pinned version.
# Captured, not piped, so an early-exiting reader can never SIGPIPE the binary.
reported=$("$bin" --version) || die "$bin --version failed"
[ "${reported%%$'\n'*}" = "goss version $version" ] \
    || die "$bin does not report goss version $version"

echo "$bin"