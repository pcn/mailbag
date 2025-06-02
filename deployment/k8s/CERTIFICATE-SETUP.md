# Certificate Setup for Mailbag Kubernetes Deployment

This document provides detailed instructions for setting up TLS certificates for your Mailbag deployment on Kubernetes (k3s/k0s).

## Prerequisites

Before proceeding, ensure you have:
1. Configured DNS records for your mail domains
2. Generated your `context.json` file using `/generate-context.sh`
3. Created the Kubernetes namespace specified in your context.json
4. Built the `render-template` utility (run `make render-template` from project root)

## Certificate Setup Options

Choose one of the following methods based on your environment:

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

## Verifying Certificate Creation

After running one of the above methods, verify that the certificates were successfully created:

```bash
# Check if certificates were created on the host
sudo ls -la /etc/letsencrypt/live/
```

You should see directories for each of your domains with certificates inside.

## Automatic Certificate Renewal

The Mailbag deployment includes a CronJob for automatic certificate renewal that will be deployed as part of the full deployment process. This is handled by the `cert-renewal.yaml` manifest in the k8s deployment directory.

When you run the `deploy-services.sh` script, it will automatically deploy this CronJob to handle certificate renewals.

## Troubleshooting

If certificate creation fails, check:

1. DNS records are correctly set up and propagated
2. Network access:
   - For HTTP validation: Port 80 is accessible from the internet
   - For DNS validation: Credentials are correct and have appropriate permissions
3. Check the logs of the certbot job:
   ```bash
   kubectl logs -n $NAMESPACE job/certbot-initial
   # or
   kubectl logs -n $NAMESPACE job/certbot-initial-dns
   ```

## Next Steps

After successfully creating certificates, proceed with the deployment of Mailbag services as described in the main deployment documentation.
