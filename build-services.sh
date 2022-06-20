#!/bin/bash
set -e -o pipefail
# set -x

# From https://stackoverflow.com/questions/49638532/docker-copy-file-to-host-from-within-dockerfile
export DOCKER_BUILDKIT=1

# Base image with packages installed 
docker build -t courier-base -f Dockerfile-base  .
# MTA image, for accepting mail delivery from the internet
docker build -t courier-mta.service -f Dockerfile-mta .
# MSA image, for allowing authenticated users to submit email delivery to other mail servers
docker build -t courier-msa.service -f Dockerfile-msa .
# IMAPD-SSL image, for checking mail via IMAP
docker build -t courier-imapd-ssl.service -f Dockerfile-iampd-ssl .
