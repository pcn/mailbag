#!/bin/bash
set -e -o pipefail
# set -x

# From https://stackoverflow.com/questions/49638532/docker-copy-file-to-host-from-within-dockerfile
export DOCKER_BUILDKIT=1

# Base image with packages installed
docker build -t support-files -f Dockerfile-support .
