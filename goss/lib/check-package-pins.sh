#!/bin/bash
# PROJ-037: the courier package versions and source checksums are declared
# once, in cue/packages.cue, and everything that compiles or checks the
# packages reads them from there. Run by goss/repo.yaml; offline.
#
#   - the pins satisfy #Packages, and each broken variant is rejected
#   - every exported build arg is a no-default ARG in Dockerfile and is read
#     by an install script, and every ARG there is exported
#   - changing cue/packages.cue changes the packages key
#   - fetch_source accepts the pinned sha256 and rejects a wrong or empty one

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

EXAMPLE=examples/example-context.json
CUE=$(scripts/fetch-cue.sh "$EXAMPLE") || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

# --- the pins and their schema ---------------------------------------------

if "$CUE" export ./cue -e packages --out json > "$work/packages.json" 2>"$work/err"; then
    ok "cue/packages.cue exports"
else
    bad "cue/packages.cue does not export:"; sed 's/^/        /' "$work/err"
    exit 1
fi

vet() { "$CUE" vet -c -d '#Packages' ./cue "$1" >"$work/err" 2>&1; }

if vet "$work/packages.json"; then
    ok "the pins satisfy #Packages"
else
    bad "the pins fail #Packages:"; sed 's/^/        /' "$work/err"
fi

# name | jq filter applied to the exported pins
while IFS='|' read -r name filter; do
    [ -n "$name" ] || continue
    jq "$filter" "$work/packages.json" > "$work/case.json"
    if vet "$work/case.json"; then
        bad "accepted: $name"
    else
        ok "rejected: $name"
    fi
done <<'EOF'
a version that is not dotted numbers|.courier.version = "latest"
a sha256 that is not 64 hex characters|.courier.sha256 = "abc123"
an uppercase sha256|.courier.sha256 |= ascii_upcase
a package with no sha256|del(.courier_authlib.sha256)
a missing package|del(.sysconftool)
an unknown package|.maildrop = .courier
EOF

# --- build args, Dockerfile ARGs, install scripts ---------------------------

"$CUE" export ./cue -e build_args --out text | cut -d= -f1 | sort > "$work/exported"
sed -n 's/^ARG //p' Dockerfile | tr ' ' '\n' | grep -v '^$' | sort > "$work/declared"

if [ "$(wc -l < "$work/exported")" -eq 8 ]; then
    ok "build_args has a VERSION and a SHA256 line for each of the 4 packages"
else
    bad "build_args has $(wc -l < "$work/exported") names, expected 8"
fi
if grep -q = "$work/declared"; then
    bad "a Dockerfile ARG has a default: $(grep = "$work/declared" | tr '\n' ' ')"
else
    ok "no Dockerfile ARG has a default"
fi
if diff -u "$work/exported" "$work/declared" > "$work/err"; then
    ok "the Dockerfile declares exactly the exported build args"
else
    bad "Dockerfile ARGs and exported build args differ:"; sed 's/^/        /' "$work/err"
fi
while read -r arg; do
    if grep -q "\${$arg[:}]" install-scripts/install-*.sh; then
        ok "an install script reads $arg"
    else
        bad "no install script reads $arg"
    fi
done < "$work/exported"

# --- the packages key covers the pins ---------------------------------------

mkdir -p "$work/tree/scripts" "$work/tree/cue"
cp -r Dockerfile install-scripts "$work/tree/"
cp scripts/packages-key.sh "$work/tree/scripts/"
cp cue/packages.cue "$work/tree/cue/"
before=$("$work/tree/scripts/packages-key.sh")
echo '// changed' >> "$work/tree/cue/packages.cue"
after=$("$work/tree/scripts/packages-key.sh")
if [ "$before" = "$(scripts/packages-key.sh)" ] && [ "$before" != "$after" ]; then
    ok "changing cue/packages.cue changes the packages key"
else
    bad "packages key did not follow cue/packages.cue ($before -> $after)"
fi

# --- fetch_source verifies the checksum, offline via SOURCE_DIR -------------

mkdir -p "$work/src" "$work/dl"
echo 'not really a tarball' > "$work/src/fixture.tar.bz2"
good=$(sha256sum "$work/src/fixture.tar.bz2" | cut -d' ' -f1)
wrong=$(printf '%064d' 0)
fetch() {
    (cd "$work/dl" && rm -f fixture.tar.bz2 &&
     SOURCE_DIR="$work/src" bash -c \
       '. "$1" && fetch_source fixture "fixture.tar.bz2" "$2"' _ \
       "$OLDPWD/install-scripts/fetch-source.sh" "$1") >"$work/err" 2>&1
}
if fetch "$good"; then ok "fetch_source accepts the matching sha256"
else bad "fetch_source rejected the matching sha256:"; sed 's/^/        /' "$work/err"; fi
if fetch "$wrong"; then bad "fetch_source accepted a wrong sha256"
else ok "fetch_source rejects a wrong sha256"; fi
if fetch ""; then bad "fetch_source accepted an empty sha256"
else ok "fetch_source rejects an empty sha256"; fi

exit "$fail"
