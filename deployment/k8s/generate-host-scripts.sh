#!/bin/bash
# This script generates host preparation scripts using the context.json and templates

set -e

# Get the git repository root directory
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Check if render-template exists
if [ ! -f "$REPO_ROOT/render-template" ]; then
  echo "Error: render-template not found."
  echo "Please run 'cd $REPO_ROOT && make render-template' first."
  exit 1
fi

# Check if context.json exists
if [ ! -f /etc/mailbag/context.json ]; then
  echo "Error: /etc/mailbag/context.json not found."
  echo "Please run ./generate-context.sh first."
  exit 1
fi

# Generate prepare-host.sh from template
"$REPO_ROOT/render-template" --context /etc/mailbag/context.json --template "$REPO_ROOT/deployment/k8s/prepare-host.sh.template" > "$REPO_ROOT/deployment/k8s/prepare-host.sh"

# Make it executable
chmod +x "$REPO_ROOT/deployment/k8s/prepare-host.sh"

echo "Host preparation script generated at $REPO_ROOT/deployment/k8s/prepare-host.sh"
echo "Run this script as root to prepare your host for Mailbag deployment"
