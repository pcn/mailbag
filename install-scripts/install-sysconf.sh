#!/bin/bash

set -e -u -o pipefail

# Version and checksum come from cue/packages.cue, as build args.
VER=${SYSCONFTOOL_VERSION:?build arg SYSCONFTOOL_VERSION not set}
. "$(dirname "$0")/fetch-source.sh"
# Download per https://www.courier-mta.org/download.html
mkdir /tmp/sysconf
cd /tmp/sysconf

fetch_source "sysconftool/${VER}" "sysconftool-${VER}.tar.bz2" "${SYSCONFTOOL_SHA256:-}"

tar xvf sysconftool-${VER}.tar.bz2

cd sysconftool-${VER}

./courier-debuild -us -uc

cd deb && sudo apt install -y ./*.deb
cp *.deb /export
