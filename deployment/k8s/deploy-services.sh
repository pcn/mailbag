#!/bin/bash
set -e

# Get the repository root
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Get namespace from context.json
NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)

# Create the namespace if it doesn't exist
kubectl get namespace $NAMESPACE &>/dev/null || kubectl create namespace $NAMESPACE

# Apply storage resources only if they don't exist
if ! kubectl get pvc -n $NAMESPACE courier-spool-pvc &>/dev/null; then
  echo "Applying storage configuration..."
  kubectl apply -f storage.yaml
else
  echo "Storage already exists, skipping storage.yaml"
fi

# Function to add hostPath volume for context.json to a manifest
add_context_volume() {
  local service=$1
  local tmpfile=$(mktemp)
  
  echo "Rendering $service manifest..."
  
  # First, render the base service manifest
  "$REPO_ROOT/render-template" \
    --template "$service.yaml" \
    --context /etc/mailbag/context.json \
    > "$tmpfile"
  
  echo "Applying $service manifest..."
  kubectl apply -f "$tmpfile"
  rm "$tmpfile"
}

# Deploy each service
for service in courierd courier-mta courier-mta-ssl courier-imapd-ssl courier-msa; do
  echo "Deploying $service..."
  add_context_volume "$service"
done

# Also handle the cert-renewal cronjob
echo "Deploying cert-renewal job..."
add_context_volume "cert-renewal"

echo "All services deployed successfully!"
