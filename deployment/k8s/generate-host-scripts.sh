#!/bin/bash
# This script generates host preparation scripts using the context.json and templates

set -e

# Check if render-template exists
if [ ! -f /home/pcn/dvcs/pcn/mailbag/render-template ]; then
  echo "Error: render-template not found."
  echo "Please run 'cd /home/pcn/dvcs/pcn/mailbag && make render-template' first."
  exit 1
fi

# Check if context.json exists
if [ ! -f /etc/mailbag/context.json ]; then
  echo "Error: /etc/mailbag/context.json not found."
  echo "Please run ./generate-context.sh first."
  exit 1
fi

# Generate prepare-host.sh from template
/home/pcn/dvcs/pcn/mailbag/render-template --context /etc/mailbag/context.json --template /home/pcn/dvcs/pcn/mailbag/deployment/k8s/prepare-host.sh.template > /home/pcn/dvcs/pcn/mailbag/deployment/k8s/prepare-host.sh

# Make it executable
chmod +x /home/pcn/dvcs/pcn/mailbag/deployment/k8s/prepare-host.sh

echo "Host preparation script generated at /home/pcn/dvcs/pcn/mailbag/deployment/k8s/prepare-host.sh"
echo "Run this script as root to prepare your host for Mailbag deployment"
