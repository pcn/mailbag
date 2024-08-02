#!/bin/bash

set -e -u -o pipefail

VER=0.72.1
# Download per https://www.courier-mta.org/download.html
mkdir /tmp/auth
cd /tmp/auth

curl -L https://sourceforge.net/projects/courier/files/authlib/${VER}/courier-authlib-${VER}.tar.bz2/download  > courier-authlib-${VER}.tar.bz2

tar xvf courier-authlib-${VER}.tar.bz2

cd courier-authlib-${VER}

sudo apt install -y libmariadb-dev libmariadb-dev-compat libpq-dev libpam0g-dev
./courier-debuild -us -uc

cd deb && sudo apt install -y ./*.deb
cp *.deb /export

