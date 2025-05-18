# Mailbag Kubernetes Deployment

This directory contains Kubernetes manifests for deploying the Mailbag mail system on a Kubernetes cluster. These manifests are designed for a single-node deployment using k0s or k3s.

## Prerequisites

1. A running Kubernetes cluster (k0s or k3s)
2. `kubectl` configured to communicate with your cluster
3. Mailbag's render-template utility built (`make render-template` from the project root)
4. TLS certificates (using Let's Encrypt or another provider)

## Setup Process

Mailbag deployment involves these key steps:

1. Generate a customized context.json configuration
2. Prepare the host machine with required directories and permissions
3. Deploy the Kubernetes manifests
4. Manage mail users as needed

## 1. Configuration Setup

Use the included script to generate a customized context.json file:

```bash
# Make scripts executable
chmod +x *.sh
chmod +x ../../generate-context.sh

# Generate context.json with your mail domain settings
sudo ../../generate-context.sh
```

This script will prompt you for:
- Your mail domain name
- Hostnames for mail services
- Storage paths
- Certificate paths

## 2. Host Preparation

After generating the context.json, prepare your host with the required directories and permissions:

```bash
# Generate the host preparation script from your context.json
./generate-host-scripts.sh

# Run the generated script to set up the host
sudo ./prepare-host.sh
```

This automatically:
- Creates all required directories
- Sets up the vmail user
- Configures proper permissions
- Prepares storage locations

## 3. Kubernetes Deployment

After host preparation, apply the manifests to your Kubernetes cluster:

1. Use the render-template utility to create Kubernetes manifests that reference your host path for context.json:
   ```bash
   # Create a template for the context.json hostPath volume and volumeMount
   cat > context-volume-patch.yaml << "EOF"
   spec:
     template:
       spec:
         volumes:
         - name: context-json
           hostPath:
             path: /etc/mailbag/context.json
             type: File
         containers:
         - name: {{CONTAINER_NAME}}
           volumeMounts:
           - name: context-json
             mountPath: /etc/mailbag/context.json
             subPath: context.json
             readOnly: true
EOF
   ```

   This way, all pods will directly use the original context.json file from the host, maintaining a single source of truth.

2. Deploy the namespace and storage resources:
   ```bash
   # Get the namespace from context.json
   NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)
   
   # Create the namespace
   kubectl create namespace $NAMESPACE
   
   # Apply storage resources
   kubectl apply -f storage.yaml
   ```

3. Create a unified deployment script to handle context.json mounting for all services:
   ```bash
   # Create a deployment script
   cat > deploy-services.sh << "EOF"
   #!/bin/bash
   set -e
   
   # Get the repository root
   REPO_ROOT="$(git rev-parse --show-toplevel)"
   
   # Get namespace from context.json
   NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)
   
   # Function to add hostPath volume for context.json to a manifest
   add_context_volume() {
     local service=$1
     local tmpfile=$(mktemp)
     
     # First, render the base service manifest
     "$REPO_ROOT/render-template" \
       --template "$service.yaml" \
       --context /etc/mailbag/context.json \
       > "$tmpfile"
     
     # Add the volume and volumeMount using sed
     # This is a simplified approach - in practice, a YAML parser would be better
     sed -i '/volumes:/a \        - name: context-json\n          hostPath:\n            path: /etc/mailbag/context.json\n            type: File' "$tmpfile"
     sed -i '/volumeMounts:/a \        - name: context-json\n          mountPath: /etc/mailbag/context.json\n          subPath: context.json\n          readOnly: true' "$tmpfile"
     
     # Apply the modified manifest
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
   EOF
   
   # Make the script executable
   chmod +x deploy-services.sh
   
   # Run the deployment script
   ./deploy-services.sh
   ```

Note: The cert-renewal job is already deployed as part of the deployment script above.

## Verifying the Deployment

1. Check that all pods are running:
   ```bash
   kubectl get pods -n mailbag
   ```

2. Verify the services are exposed:
   ```bash
   kubectl get services -n mailbag
   ```

3. Test mail delivery by sending a test email.

## 4. Managing User Accounts

Use the included interactive user management script:

```bash
sudo ./manage-mail-users.sh
```

This script provides a menu-driven interface to:
- Add new mail users
- Delete existing mail users
- List all configured mail users

The script automatically handles:
- Creating userdb entries with proper settings
- Creating maildir structures
- Setting correct permissions
- Updating the authentication database

## Verifying the Deployment

1. Check that all pods are running:
   ```bash
   kubectl get pods -n mailbag
   ```

2. Verify the services are exposed:
   ```bash
   kubectl get services -n mailbag
   ```

3. Test mail delivery by sending a test email.

## 5. Validating Your Deployment

Mailbag includes a goss-based validation system to verify that your deployment is correctly set up. After completing all the deployment steps, run the following command to validate your configuration:

```bash
# Install goss if not already installed
if ! command -v goss &> /dev/null; then
  curl -L https://github.com/aelsabbahy/goss/releases/download/v0.4.8/goss-linux-amd64 -o goss
  chmod +x goss
  sudo mv goss /usr/local/bin/
fi

# Run validation using your context.json
cd /home/pcn/dvcs/pcn/mailbag
goss -g goss/goss.yaml --vars /etc/mailbag/context.json validate
```

This will check:
- That all required Kubernetes resources exist (namespace, pods, services)
- That all required processes are running
- That all directory structures and file permissions are correct
- That certificates exist and are accessible
- That DNS resolution works for your mail domains
- That the Kubernetes API is responding

If any tests fail, goss will provide specific details about what's wrong, helping you troubleshoot your deployment.

## Troubleshooting

- Check pod logs: `kubectl logs -n mailbag <pod-name>`
- Verify volume mounts: `kubectl describe pod -n mailbag <pod-name>`
- Check permissions on host directories: `ls -la /mailbag/spool/courier/`
- Check the context.json file: `cat /etc/mailbag/context.json`
- Ensure certificates exist at the specified paths
- Review goss validation output for specific failures
