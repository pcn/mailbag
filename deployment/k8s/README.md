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

# Generate context.json with your mail domain settings
sudo ./generate-context.sh
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

1. First, update the ConfigMap with your context.json content:
   ```bash
   # Copy your context.json content to the configmap.yaml file
   CONTEXT_JSON=$(cat /etc/mailbag/context.json)
   sed -i "s|context.json: .*|context.json: |
$CONTEXT_JSON|" configmap.yaml
   ```
   
   Or manually edit configmap.yaml to include your context.json content.

2. Deploy the namespace and storage resources:
   ```bash
   kubectl apply -f namespace.yaml
   kubectl apply -f storage.yaml
   ```

3. Deploy the configuration:
   ```bash
   kubectl apply -f configmap.yaml
   ```

4. Deploy the core mail services:
   ```bash
   kubectl apply -f courierd.yaml
   kubectl apply -f courier-mta.yaml
   kubectl apply -f courier-mta-ssl.yaml
   kubectl apply -f courier-imapd-ssl.yaml
   kubectl apply -f courier-msa.yaml
   ```

5. (Optional) Deploy the certificate renewal cron job:
   ```bash
   kubectl apply -f cert-renewal.yaml
   ```

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

## Troubleshooting

- Check pod logs: `kubectl logs -n mailbag <pod-name>`
- Verify volume mounts: `kubectl describe pod -n mailbag <pod-name>`
- Check permissions on host directories: `ls -la /mailbag/spool/courier/`
- Check the context.json file: `cat /etc/mailbag/context.json`
- Ensure certificates exist at the specified paths
