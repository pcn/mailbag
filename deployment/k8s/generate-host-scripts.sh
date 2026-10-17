#!/bin/bash
# This script generates host preparation scripts using the context.json and templates

set -e

# Get the git repository root directory
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Check if context.json exists
if [ ! -f /etc/mailbag/context.json ]; then
  echo "Error: /etc/mailbag/context.json not found."
  echo "Please run ./generate-context.sh first."
  exit 1
fi

# The renderer version comes from the host's context.
RENDERER=$("$REPO_ROOT/scripts/fetch-renderer.sh" /etc/mailbag/context.json)

# Generate prepare-host.sh from template
"$RENDERER" --strict -n "$REPO_ROOT/deployment/k8s/prepare-host.sh.template" /etc/mailbag/context.json > "$REPO_ROOT/deployment/k8s/prepare-host.sh"

# Generate mail-certificates.yaml from template
"$RENDERER" --strict -n "$REPO_ROOT/deployment/k8s/mail-certificates.yaml.template" /etc/mailbag/context.json > "$REPO_ROOT/deployment/k8s/mail-certificates.yaml"

# Make it executable
chmod +x "$REPO_ROOT/deployment/k8s/prepare-host.sh"

echo "Host preparation script generated at $REPO_ROOT/deployment/k8s/prepare-host.sh"
echo "Certificate configuration generated at $REPO_ROOT/deployment/k8s/mail-certificates.yaml"
echo "Run this script as root to prepare your host for Mailbag deployment"
