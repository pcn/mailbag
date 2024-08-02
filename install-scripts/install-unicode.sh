#!/bin/bash

set -e -u -o pipefail

VER=2.3.0
# Download per https://www.courier-mta.org/download.html
mkdir /tmp/unicode
cd /tmp/unicode

curl -L https://sourceforge.net/projects/courier/files/courier-unicode/${VER}/courier-unicode-${VER}.tar.bz2/download >  courier-unicode-${VER}.tar.bz2

tar xvf courier-unicode-${VER}.tar.bz2

cd courier-unicode-${VER}

./courier-debuild -us -uc

cd deb && sudo apt install -y ./*.deb
cp *.deb /export
