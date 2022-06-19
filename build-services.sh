#!/bin/bash
set -e -o pipefail
# set -x

# From https://stackoverflow.com/questions/49638532/docker-copy-file-to-host-from-within-dockerfile
export DOCKER_BUILDKIT=1

docker build -t syslog -f Dockerfile-rsyslog .
docker build -t courier-base -f Dockerfile-base  .

docker build -t courier-mta.service -f Dockerfile-mta .
