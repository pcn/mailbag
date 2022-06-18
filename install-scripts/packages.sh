#!/bin/bash

# doing this all in docker starts to get clumsy in the face
# of failure and retries

while ! echo y | apt-get install -y \
                         build-essential curl git gnupg  wget \
            software-properties-common rsync emacs-nox zip vim sudo \
            zlib1g-dev libelf-dev libffi-dev libsqlite3-dev \
            libbz2-dev libreadline-dev libssl-dev libedit-dev \
            jq python3 bind9-host devscripts libldap2-dev mime-support \
            expect libgdbm-dev libidn11-dev gnutls-dev gnutls-bin \
            libgcrypt-dev ghostscript mgetty-fax netpbm aspell \
            libpcre2-dev libaspell-dev libperl-dev debhelper locales; do   
    sleep 1
done

update-alternatives --install /usr/bin/python python /usr/bin/python3 1000

