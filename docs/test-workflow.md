# Mailbag Test Workflow

This document outlines a comprehensive test workflow for validating your Mailbag deployment, including the necessary steps for setting up certificates and verifying that all components work correctly.

## Prerequisites

Before starting the test workflow, ensure you have:

1. A domain name that you control (we'll use `example.com` in these examples)
2. A server with a public IP address
3. DNS records properly configured:
   - A records for `mail.example.com`, `imap.example.com`, and `smtp.example.com`
   - MX record pointing to `mail.example.com` 
   - SPF, DKIM, and DMARC records (optional but recommended)
4. A Kubernetes cluster (k0s or k3s) installed on your server
5. `kubectl` configured to interact with your cluster
6. Necessary ports (25, 587, 993) accessible on your server

## 0. System Preparation

### Install System Dependencies

On a fresh Debian-based system (Ubuntu, Debian, etc.), you'll need to install some basic dependencies:

```bash
# Update package lists and install required packages
sudo apt update
sudo apt install -y git build-essential pkg-config libssl-dev jq curl
```

### Build the Template Renderer

Next, build the `render-template` utility that's used throughout the deployment process:

```bash
# Install Rust if not already installed
# See https://www.rust-lang.org/tools/install for detailed installation instructions
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# Build the template renderer
cd templater/
cargo build --release
cd ..

# Create a symbolic link to make it easier to use
ln -sf $(pwd)/templater/target/release/render-template .
```

This tool will be used to render Kubernetes manifests and configuration files using values from your context.json file.

## 1. Certificate Setup with Let's Encrypt

Mailbag includes a container for certificate management using certbot. For testing purposes, you'll need to obtain initial certificates that the deployment can use.

### Initial Certificate Setup

You have two options for obtaining your initial certificates:

#### Option 1: Using the Included Certbot Container

```bash

# First, generate your context.json with your domain settings
sudo ./generate-context.sh

# Create the namespace using the value from context.json
NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)
kubectl create namespace $NAMESPACE

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
./render-template \
  --template certbot-initial-job.yaml \
  --context /etc/mailbag/context.json \
  --var NAMESPACE=mailbag \
  --var MTA_HOSTNAME={{mta.dns_name}} \
  --var IMAPD_HOSTNAME={{imapd_ssl.dns_name}} \
  --var MTASSL_HOSTNAME={{mta_ssl.dns_name}} \
  --var DOMAIN={{domain.zone}} \
  > certbot-initial-job-rendered.yaml

# Apply the rendered job manifest
kubectl apply -f certbot-initial-job-rendered.yaml
```

Ensure port 80 is accessible from the internet for HTTP validation.

#### Option 2: Using DNS Validation

If port 80 is not accessible, create a custom job that uses DNS validation:

```bash
# Create a ConfigMap with your DNS provider credentials
kubectl create configmap -n mailbag dns-credentials --from-file=/path/to/your/credentials.ini

# Create a temporary DNS validation job manifest using your context.json
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

# Use render-template to populate the job manifest with values from context.json
./render-template \
  --template certbot-initial-dns-job.yaml \
  --context /etc/mailbag/context.json \
  --var NAMESPACE=mailbag \
  --var MTA_HOSTNAME={{mta.dns_name}} \
  --var IMAPD_HOSTNAME={{imapd_ssl.dns_name}} \
  --var MTASSL_HOSTNAME={{mta_ssl.dns_name}} \
  --var DOMAIN={{domain.zone}} \
  > certbot-initial-dns-job-rendered.yaml

# Apply the rendered job manifest
kubectl apply -f certbot-initial-dns-job-rendered.yaml
```

Adjust the DNS provider plugin and configuration for your specific DNS provider.

### Automatic Certificate Renewal

The Mailbag deployment includes a CronJob for automatic certificate renewal in `cert-renewal.yaml`. You'll deploy this as part of the full deployment process.

## 2. Generate Configuration

```bash

# Make scripts executable
chmod +x generate-context.sh
chmod +x deployment/k8s/*.sh

# Generate the context.json file
sudo ./generate-context.sh
```

When prompted, enter your domain name and other configuration details. 
Make sure to specify the correct path for certificates (default: `/etc/letsencrypt/live`).

## 3. Prepare the Host

```bash
cd deployment/k8s

# Generate and run the host preparation script
sudo ./generate-host-scripts.sh
sudo ./prepare-host.sh
```

## 4. Deploy Mailbag to Kubernetes

```bash
# Update the configmap.yaml with your context.json
./render-template \
  --template configmap.yaml \
  --context /etc/mailbag/context.json \
  > configmap-rendered.yaml

# Deploy the Kubernetes resources
kubectl apply -f storage.yaml
kubectl apply -f configmap-rendered.yaml

# Render and apply the remaining manifests
for manifest in courierd.yaml courier-mta.yaml courier-mta-ssl.yaml courier-imapd-ssl.yaml courier-msa.yaml cert-renewal.yaml; do
  ./render-template \
    --template $manifest \
    --context /etc/mailbag/context.json \
    | kubectl apply -f -
done
```

## 5. Add a Test User

```bash
# Run the user management script to add a test user
sudo ./manage-mail-users.sh
```

When prompted, select option 1 to add a new user, and enter:
- Username: `testuser`
- Domain: Your domain (e.g., `example.com`)
- Password: Create a secure password

## 6. Validate the Deployment

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

## 7. Test Email Functionality

### Test SMTP (Sending Email)

Use a mail client or command line to send an email:

```bash
# Send a test email via command line
DOMAIN=$(jq -r '.domain.zone' /etc/mailbag/context.json)
SMTP_HOST=$(jq -r '.mta_ssl.dns_name' /etc/mailbag/context.json)
CERT_PATH=$(jq -r '.mta.tls_certfile' /etc/mailbag/context.json | sed 's|/fullchain.pem$||')

echo "Subject: Test Email" | openssl s_client -connect $SMTP_HOST:587 -starttls smtp -crlf -quiet -ign_eof \
  -CAfile $CERT_PATH/fullchain.pem -CApath /etc/ssl/certs \
  -auth LOGIN -user testuser@$DOMAIN -pass "YourPassword"
```

### Test IMAP (Receiving Email)

Use a mail client or command line to connect to IMAP:

```bash
# Check IMAP connection
IMAP_HOST=$(jq -r '.imapd_ssl.dns_name' /etc/mailbag/context.json)
CERT_PATH=$(jq -r '.imapd_ssl.tls_certfile' /etc/mailbag/context.json | sed 's|/fullchain.pem$||')

openssl s_client -connect $IMAP_HOST:993 -crlf -quiet \
  -CAfile $CERT_PATH/fullchain.pem -CApath /etc/ssl/certs

# After connected, authenticate with: 
# a login testuser@$DOMAIN YourPassword
# b select INBOX
# c status INBOX (messages)
```

### Full Mail Flow Test

For a complete test:

1. Send an email from an external account (Gmail, etc.) to `testuser@$DOMAIN` (where $DOMAIN is your domain from context.json)
2. Check that the email is received using IMAP connection
3. Reply to the email using your mail client configured with the Mailbag server
4. Verify that the reply is received by the external account

## 8. Troubleshooting

If you encounter issues during testing:

### Certificate Issues
- Verify certificates exist: `ls -la $(jq -r '.mta.tls_certfile' /etc/mailbag/context.json | sed 's|/fullchain.pem$||')/`
- Check certificate validity: `openssl x509 -in $(jq -r '.mta.tls_certfile' /etc/mailbag/context.json) -text -noout`

### DNS Issues
- Check DNS records: `dig MX $(jq -r '.domain.zone' /etc/mailbag/context.json)`, `dig A $(jq -r '.mta.dns_name' /etc/mailbag/context.json)`
- Verify reverse DNS is set up properly

### Kubernetes Issues
- Check pod status: `kubectl get pods -n mailbag`
- View pod logs: `kubectl logs -n mailbag pod-name`
- Check persistent volumes: `kubectl get pv,pvc -n mailbag`

### Mail Delivery Issues
- Check mail logs: `kubectl logs -n mailbag courier-mta-pod-name`
- Verify port connectivity: `telnet $(jq -r '.mta.dns_name' /etc/mailbag/context.json) 25`, `telnet $(jq -r '.mta_ssl.dns_name' /etc/mailbag/context.json) 587`
- Test SMTP with verbose output: `DOMAIN=$(jq -r '.domain.zone' /etc/mailbag/context.json); SMTP_HOST=$(jq -r '.mta_ssl.dns_name' /etc/mailbag/context.json); swaks --to testuser@$DOMAIN --server $SMTP_HOST:587`

## 9. Performance Testing

To test the performance of your mail server:

```bash
# Send multiple test emails
DOMAIN=$(jq -r '.domain.zone' /etc/mailbag/context.json)
SMTP_HOST=$(jq -r '.mta_ssl.dns_name' /etc/mailbag/context.json)
CERT_PATH=$(jq -r '.mta.tls_certfile' /etc/mailbag/context.json | sed 's|/fullchain.pem$||')

for i in $(seq 1 10); do
  echo "Subject: Test Email $i" | openssl s_client -connect $SMTP_HOST:587 -starttls smtp -crlf -quiet -ign_eof \
    -CAfile $CERT_PATH/fullchain.pem -CApath /etc/ssl/certs \
    -auth LOGIN -user testuser@$DOMAIN -pass "YourPassword"
done
```

## 10. Clean Up (if needed)

To remove the deployment:

```bash
kubectl delete namespace mailbag
```

Note that this will remove all Kubernetes resources but not the data on persistent volumes.
