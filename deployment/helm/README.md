# Mailbag Helm Chart

This directory contains a Helm chart for deploying the Mailbag mail system on a Kubernetes cluster. The chart is designed to work with Argo CD for GitOps-based deployments.

## Prerequisites

1. A running Kubernetes cluster (k0s or k3s)
2. Helm 3.x installed
3. Argo CD installed in your cluster (for GitOps deployment)
4. Host directories prepared for persistent storage
5. TLS certificates (using Let's Encrypt or another provider)

## Host Preparation

Before deploying, prepare the host directories for persistent storage as described in the Kubernetes manifests README.

## Chart Structure

```
mailbag/
├── Chart.yaml            # Chart metadata
├── values.yaml           # Default configuration values
└── templates/            # Kubernetes manifest templates
    ├── namespace.yaml
    ├── storage.yaml
    ├── configmap.yaml
    ├── courierd.yaml
    ├── courier-mta.yaml
    ├── courier-mta-ssl.yaml
    ├── courier-imapd-ssl.yaml
    ├── courier-msa.yaml
    ├── cert-renewal.yaml
    └── NOTES.txt
```

## Configuration

The `values.yaml` file contains the default configuration values. You can customize these values by creating your own values file.

Key configuration sections:

- **namespace**: Configure the Kubernetes namespace
- **image**: Configure container image settings
- **storage**: Configure persistent volume storage paths and sizes
- **mail**: Configure mail domains and hostnames
- **certificates**: Configure TLS certificate paths and renewal
- **services**: Configure service ports and exposure
- **components**: Enable/disable and configure individual mail components

## Deploying with Helm

To deploy the Mailbag system directly with Helm:

```bash
# Install the chart with default values
helm install mailbag ./mailbag

# Install with custom values
helm install mailbag ./mailbag -f my-values.yaml

# Upgrade an existing deployment
helm upgrade mailbag ./mailbag -f my-values.yaml
```

## Deploying with Argo CD

1. Add your git repository to Argo CD (via UI or CLI)

2. Create an Application in Argo CD:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mailbag
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/pcn/mailbag.git
    targetRevision: HEAD
    path: deployment/helm
  destination:
    server: https://kubernetes.default.svc
    namespace: mailbag
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

3. Apply this manifest:

```bash
kubectl apply -f mailbag-application.yaml
```

Argo CD will now monitor your git repository and automatically sync changes to your Kubernetes cluster.

## Customizing for Production

For production deployments, create a custom values file that overrides the defaults:

```yaml
# production-values.yaml
mail:
  domain: yourdomain.com
  hostname: mail
  acceptMailFor:
    - yourdomain.com
    - mail.yourdomain.com

# Add other customizations as needed
```

Then deploy or update using this values file:

```bash
# With Helm
helm upgrade --install mailbag ./mailbag -f production-values.yaml

# With Argo CD
# Update your Application manifest to include the values file:
spec:
  source:
    repoURL: https://github.com/pcn/mailbag.git
    targetRevision: HEAD
    path: deployment/helm
    helm:
      valueFiles:
      - production-values.yaml
```

## Testing the Deployment

After deployment, verify all components are running:

```bash
kubectl get pods -n mailbag
kubectl get services -n mailbag
```

## Troubleshooting

- Check pod logs: `kubectl logs -n mailbag <pod-name>`
- Check persistent volumes: `kubectl get pv,pvc -n mailbag`
- Verify ConfigMap: `kubectl get configmap -n mailbag mailbag-context -o yaml`
