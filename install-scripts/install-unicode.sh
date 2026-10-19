#!/bin/bash

set -e -u -o pipefail

# Version and checksum come from cue/packages.cue, as build args.
VER=${COURIER_UNICODE_VERSION:?build arg COURIER_UNICODE_VERSION not set}
. "$(dirname "$0")/fetch-source.sh"
# Download per https://www.courier-mta.org/download.html
mkdir /tmp/unicode
cd /tmp/unicode

fetch_source "courier-unicode/${VER}" "courier-unicode-${VER}.tar.bz2" "${COURIER_UNICODE_SHA256:-}"

tar xvf courier-unicode-${VER}.tar.bz2

cd courier-unicode-${VER}

./courier-debuild -us -uc

cd deb && sudo apt install -y ./*.deb
cp *.deb /export
