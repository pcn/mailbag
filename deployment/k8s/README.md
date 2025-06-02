# Mailbag Kubernetes Deployment

This directory contains Kubernetes manifests for deploying the Mailbag mail system on a Kubernetes cluster. These manifests are designed for a single-node deployment using k0s or k3s.

## Prerequisites

1. A running Kubernetes cluster (k0s or k3s)
2. `kubectl` configured to communicate with your cluster
3. Mailbag's render-template utility built (`make render-template` from the project root)
4. TLS certificates (will be set up in step 3)

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

## 3. Certificate Setup

Before deploying services, you need to set up TLS certificates. First create the Kubernetes namespace that will be used for your deployment:

```bash
# Get namespace from context.json
NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)

# Create namespace
kubectl create namespace $NAMESPACE
```

Then choose one of the following methods based on your environment:

### Option 1: Using HTTP Validation (Port 80 must be accessible)

This method requires that port 80 is accessible from the internet for the Let's Encrypt HTTP validation challenge.

```bash
# Create a temporary job manifest using your context.json
cat > certbot-initial-job.yaml << "EOF"
apiVersion: batch/v1
kind: Job
metadata:
  name: certbot-initial
  namespace: {{NAMESPACE}}
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: certbot
        image: ghcr.io/pcn/mailbag/support:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          certbot certonly --standalone \
            -d {{MTA_HOSTNAME}} \
            -d {{IMAPD_HOSTNAME}} \
            -d {{MTASSL_HOSTNAME}} \
            --agree-tos -m admin@{{DOMAIN}} --non-interactive
        ports:
        - containerPort: 80
        volumeMounts:
        - name: cert-storage
          mountPath: /etc/letsencrypt
      volumes:
      - name: cert-storage
        hostPath:
          path: /etc/letsencrypt
          type: DirectoryOrCreate
EOF

# Use render-template to populate the job manifest with values from context.json
NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)

./render-template \
  --template certbot-initial-job.yaml \
  --context /etc/mailbag/context.json \
  --var NAMESPACE="$NAMESPACE" \
  --var MTA_HOSTNAME=$(jq -r '.mta.dns_name' /etc/mailbag/context.json) \
  --var IMAPD_HOSTNAME=$(jq -r '.imapd_ssl.dns_name' /etc/mailbag/context.json) \
  --var MTASSL_HOSTNAME=$(jq -r '.mta_ssl.dns_name' /etc/mailbag/context.json) \
  --var DOMAIN=$(jq -r '.domain.zone' /etc/mailbag/context.json) \
  > certbot-initial-job-rendered.yaml

# Apply the rendered job manifest
kubectl apply -f certbot-initial-job-rendered.yaml

# Check job status
kubectl get jobs -n $NAMESPACE
kubectl logs -n $NAMESPACE job/certbot-initial
```

### Option 2: Using DNS Validation (If port 80 is not accessible)

If port 80 is blocked or not accessible, you can use DNS validation instead. This example uses Cloudflare, but you can adapt it to your DNS provider.

```bash
# Create a ConfigMap with your DNS provider credentials
# First, create a credentials file for your DNS provider
# For Cloudflare, create a file with:
# dns_cloudflare_email = your-email@example.com
# dns_cloudflare_api_key = your-global-api-key

# Create a ConfigMap from this file
NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)
kubectl create configmap -n $NAMESPACE dns-credentials --from-file=/path/to/your/credentials.ini

# Create a temporary DNS validation job manifest
cat > certbot-initial-dns-job.yaml << "EOF"
apiVersion: batch/v1
kind: Job
metadata:
  name: certbot-initial-dns
  namespace: {{NAMESPACE}}
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: certbot
        image: ghcr.io/pcn/mailbag/support:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          certbot certonly --dns-cloudflare \
            --dns-cloudflare-credentials /etc/letsencrypt/credentials.ini \
            -d {{MTA_HOSTNAME}} \
            -d {{IMAPD_HOSTNAME}} \
            -d {{MTASSL_HOSTNAME}} \
            --agree-tos -m admin@{{DOMAIN}} --non-interactive
        volumeMounts:
        - name: cert-storage
          mountPath: /etc/letsencrypt
        - name: credentials
          mountPath: /etc/letsencrypt/credentials.ini
          subPath: credentials.ini
      volumes:
      - name: cert-storage
        hostPath:
          path: /etc/letsencrypt
          type: DirectoryOrCreate
      - name: credentials
        configMap:
          name: dns-credentials
EOF

# Use render-template to populate the job manifest
NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)

./render-template \
  --template certbot-initial-dns-job.yaml \
  --context /etc/mailbag/context.json \
  --var NAMESPACE="$NAMESPACE" \
  --var MTA_HOSTNAME=$(jq -r '.mta.dns_name' /etc/mailbag/context.json) \
  --var IMAPD_HOSTNAME=$(jq -r '.imapd_ssl.dns_name' /etc/mailbag/context.json) \
  --var MTASSL_HOSTNAME=$(jq -r '.mta_ssl.dns_name' /etc/mailbag/context.json) \
  --var DOMAIN=$(jq -r '.domain.zone' /etc/mailbag/context.json) \
  > certbot-initial-dns-job-rendered.yaml

# Apply the rendered job manifest
kubectl apply -f certbot-initial-dns-job-rendered.yaml

# Check job status
kubectl get jobs -n $NAMESPACE
kubectl logs -n $NAMESPACE job/certbot-initial-dns
```

### Verifying Certificate Creation

After running one of the above methods, verify that the certificates were successfully created:

```bash
# Check if certificates were created on the host
sudo ls -la /etc/letsencrypt/live/
```

The certificates should be successfully created on your host system at `/etc/letsencrypt/live/` and will be used by the Mailbag services when deployed in the next step.

## 4. Kubernetes Deployment

After host preparation, apply the manifests to your Kubernetes cluster:

1. All Kubernetes manifests in this directory have been updated to reference the context.json file as a hostPath volume mount. The `context-volume-patch.yaml` file is provided as a template for adding this mount to any additional services you might create.

   This approach ensures all pods directly use the original context.json file from the host, maintaining a single source of truth.

2. Deploy all services using the provided deployment script:
   ```bash
   # Make the script executable if needed
   chmod +x deploy-services.sh
   
   # Run the deployment script
   ./deploy-services.sh
   ```
   
   This script will:
   - Create the namespace from your context.json configuration
   - Apply storage resources
   - Render and deploy all service manifests with context.json mounted from the host
   - Deploy the cert-renewal cronjob

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

## 5. Managing User Accounts

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

## 6. Validating Your Deployment

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
