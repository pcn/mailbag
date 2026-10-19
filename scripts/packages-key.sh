#!/bin/bash
# Print the content key of the packages image: pkgs-<hash of its inputs>.
#
# The packages image (Dockerfile) compiles sysconftool, courier-unicode,
# courier-authlib and courier into .debs, which takes 10-13 minutes. Its only
# inputs from the repo are Dockerfile, install-scripts/ and the versions and
# checksums in cue/packages.cue (passed as build args), so a hash over exactly
# those files names what it would compile. CI tags the image with this
# key, compiles only when no image carries it yet, and builds the base FROM it --
# so identical inputs are compiled once, on whichever branch gets there first,
# and a base can never be paired with packages built from different scripts.
#
# The hash covers each file's path and contents, not mtimes, so a checkout
# anywhere produces the same key. The workflow file is deliberately not an
# input: changing how jobs are wired does not change what is compiled.

set -e -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

hash=$(find Dockerfile install-scripts cue/packages.cue -type f -print0 \
           | LC_ALL=C sort -z \
           | xargs -0 sha256sum \
           | sha256sum \
           | cut -c1-16)
echo "pkgs-$hash"