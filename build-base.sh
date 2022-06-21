#!/bin/bash
set -e -o pipefail
# set -x

# From https://stackoverflow.com/questions/49638532/docker-copy-file-to-host-from-within-dockerfile
export DOCKER_BUILDKIT=1
docker build  -t build-mail -f Dockerfile  .
# docker build --output type=tar,dest=courier-packages.tar .

# Based on this:
# https://stackoverflow.com/questions/51086724/docker-build-using-volumes-at-build-time

# Remember to add the right github ssh key to this image
# ssh-add ~/.ssh/id_github || ssh-add ~/.ssh/id_github_ed25519
# Gotta run the script manually, I guess?
# export tmp_container=$( docker run -w /home/pcn -v $SSH_AUTH_SOCK:$SSH_AUTH_SOCK -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK --entrypoint=./initialize-ansible.sh nlf )

# bash ./update.sh
