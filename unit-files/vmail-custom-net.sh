#!/bin/bash

(/usr/bin/docker network ls  | grep $( jq -r .docker.network_name /etc/mailbag/context.json )) || \
  /usr/bin/docker network create $( jq -r .docker.network_name /etc/mailbag/context.json )
