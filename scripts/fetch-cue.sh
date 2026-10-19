#!/bin/bash
# Print the path of the cue binary pinned by a context.json, fetching and
# verifying it first if it is not already cached.
#
#   CUE=$(scripts/fetch-cue.sh examples/example-context.json)
#   "$CUE" vet -c -d '#Context' ./cue examples/example-context.json
#
# The version and per-target sha256 come from .tools.cue in the context, like
# fetch-goss.sh and fetch-renderer.sh. CUE releases publish no checksums file;
# the pinned values are the sha256 digests GitHub records for each release
# asset (gh api repos/cue-lang/cue/releases/tags/<version>, .assets[].digest).

set -e -u -o pipefail

CONTEXT="${1:?usage: $0 CONTEXT_JSON}"
CACHE="${MAILBAG_TOOL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mailbag}"

die() { echo "fetch-cue: $*" >&2; exit 1; }

[ -r "$CONTEXT" ] || die "context not readable: $CONTEXT"
for tool in curl jq sha256sum tar; do
    command -v "$tool" >/dev/null || die "$tool not found"
done

case "$(uname -m)" in
    x86_64)  target=x86_64-unknown-linux-gnu;  asset_arch=amd64 ;;
    aarch64) target=aarch64-unknown-linux-gnu; asset_arch=arm64 ;;
    *)       die "no cue build for $(uname -m)" ;;
esac

version=$(jq -er '.tools.cue.version' "$CONTEXT") \
    || die "$CONTEXT has no .tools.cue.version"
sha256=$(jq -er --arg t "$target" '.tools.cue.sha256[$t]' "$CONTEXT") \
    || die "$CONTEXT has no .tools.cue.sha256 for $target"

dir="$CACHE/cue-$version-$target"
bin="$dir/cue"

if [ ! -x "$bin" ]; then
    tarball="cue_${version}_linux_${asset_arch}.tar.gz"
    url="https://github.com/cue-lang/cue/releases/download/$version/$tarball"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/$tarball" "$url" || die "download failed: $url"
    echo "$sha256  $tmp/$tarball" | sha256sum -c --quiet - \
        || die "sha256 mismatch for $url"
    tar -xzf "$tmp/$tarball" -C "$tmp" cue
    mkdir -p "$dir"
    # Installed under a private name, then renamed: goss runs checks in
    # parallel, and on a cold cache another one can find "$bin" executable
    # while install is still writing it. rename(2) is atomic.
    install -m 0755 "$tmp/cue" "$bin.$$"
    mv -f "$bin.$$" "$bin"
fi

# A cached binary is trusted only if it still reports the pinned version.
# Captured, not piped: `cue version | head -1` under pipefail fails whenever
# head closes the pipe before cue has written its remaining lines (SIGPIPE).
reported=$("$bin" version) || die "$bin version failed"
[ "${reported%%$'\n'*}" = "cue version $version" ] \
    || die "$bin does not report cue version $version"

echo "$bin"
