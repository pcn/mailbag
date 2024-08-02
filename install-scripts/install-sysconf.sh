#!/bin/bash

set -e -u -o pipefail

VER=0.21
# Download per https://www.courier-mta.org/download.html
mkdir /tmp/sysconf
cd /tmp/sysconf

curl -L https://sourceforge.net/projects/courier/files/sysconftool/${VER}/sysconftool-${VER}.tar.bz2/download >  sysconftool-${VER}.tar.bz2

tar xvf sysconftool-${VER}.tar.bz2

cd sysconftool-${VER}

./courier-debuild -us -uc

cd deb && sudo apt install -y ./*.deb
cp *.deb /export
