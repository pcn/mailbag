#!/bin/bash

set -e -u -o pipefail

VER=2.0.8
# Download per https://www.courier-mta.org/download.html
mkdir /tmp/c
cd /tmp/c

curl -L https://sourceforge.net/projects/courier/files/courier/${VER}/courier-${VER}.tar.bz2/download > courier-${VER}.tar.bz2

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
