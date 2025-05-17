# Mailbag Kubernetes Deployment

This directory contains Kubernetes manifests for deploying the Mailbag mail system on a Kubernetes cluster. These manifests are designed for a single-node deployment using k0s or k3s.

## Prerequisites

1. A running Kubernetes cluster (k0s or k3s)
2. `kubectl` configured to communicate with your cluster
3. Host directories prepared for persistent storage
4. TLS certificates (using Let's Encrypt or another provider)

## Preparing Host Storage

Before deploying, prepare the host directories for persistent storage:

```bash
# Base directories
mkdir -p /mailbag/spool/courier
mkdir -p /mailbag/config/courier
mkdir -p /mailbag/config/authlib
mkdir -p /vmail

# Critical courier spool subdirectories
mkdir -p /mailbag/spool/courier/msgs
mkdir -p /mailbag/spool/courier/msgq
mkdir -p /mailbag/spool/courier/track
mkdir -p /mailbag/spool/courier/tmp
mkdir -p /mailbag/spool/courier/filters
mkdir -p /mailbag/spool/courier/allfilters

# Create vmail user on host for proper permissions
groupadd -g 300 vmail
useradd -M -r -d /vmail -u 300 -g vmail vmail

# Set correct permissions
chmod 750 /mailbag/spool/courier/msgs
chmod 750 /mailbag/spool/courier/msgq
chmod 755 /mailbag/spool/courier/track
chmod 770 /mailbag/spool/courier/tmp
chmod 750 /mailbag/spool/courier/filters
chmod 750 /mailbag/spool/courier/allfilters
chmod 755 /mailbag/config/courier
chmod 700 /mailbag/config/authlib

# Set correct ownership
chown -R vmail:vmail /vmail
chown -R vmail:vmail /mailbag/spool/courier
chown -R vmail:vmail /mailbag/config/courier
chown -R vmail:vmail /mailbag/config/authlib
```

## Deployment Instructions

1. Edit the `configmap.yaml` file to configure your mail domains and other settings.

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

## Managing User Accounts

To create a mail user, you'll need to access the authlib directory:

1. Create a user entry:
   ```bash
   # On the host
   cd /mailbag/config/authlib
   userdbpw -hmac-md5 | userdb -f userdb user@example.com set hmac-md5pw
   userdb -f userdb user@example.com set gid=300
   userdb -f userdb user@example.com set uid=300
   userdb -f userdb user@example.com set home=/vmail/example.com/user
   makeuserdb
   
   # Create the maildir
   mkdir -p /vmail/example.com/user
   /usr/lib/courier/bin/maildirmake /vmail/example.com/user/Maildir
   chown -R vmail:vmail /vmail/example.com/user
   ```

## Troubleshooting

- Check pod logs: `kubectl logs -n mailbag <pod-name>`
- Verify volume mounts: `kubectl describe pod -n mailbag <pod-name>`
- Check permissions on host directories
