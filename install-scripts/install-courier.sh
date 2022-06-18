#!/bin/bash

set -e -u -o pipefail

VER=1.1.10
# Download per https://www.courier-mta.org/download.html
mkdir /tmp/c
cd /tmp/c

curl -L https://sourceforge.net/projects/courier/files/courier/${VER}/courier-${VER}.tar.bz2/download > courier-${VER}.tar.bz2

# instructions from https://www.courier-mta.org/install.html
tar -xvf courier-${VER}.tar.bz2
cd courier-${VER}

# sudo apt install -y locales
locale-gen en_US.UTF-8

./courier-debuild -us -uc

cd deb && sudo apt install -y ./*.deb
cp *.deb /export
