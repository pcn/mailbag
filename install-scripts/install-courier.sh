#!/bin/bash

set -e -u -o pipefail

# Version and checksum come from cue/packages.cue, as build args.
VER=${COURIER_VERSION:?build arg COURIER_VERSION not set}
. "$(dirname "$0")/fetch-source.sh"
# Download per https://www.courier-mta.org/download.html
mkdir /tmp/c
cd /tmp/c

fetch_source "courier/${VER}" "courier-${VER}.tar.bz2" "${COURIER_SHA256:-}"

# instructions from https://www.courier-mta.org/install.html
tar -xvf courier-${VER}.tar.bz2
cd courier-${VER}

# sudo apt install -y locales
locale-gen en_US.UTF-8

# nocheck: the same libs/rfc2045 IDN test expectation as courier-authlib (see
# install-auth.sh) -- test3@ and test13@tèst.example.com expected with a raw
# Latin-1 byte, produced as UTF-8 on noble. Re-enable once upstream's
# reference output matches.
DEB_BUILD_OPTIONS=nocheck ./courier-debuild -us -uc

cd deb && sudo apt install -y ./*.deb
cp *.deb /export
