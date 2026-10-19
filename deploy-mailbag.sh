#!/bin/bash
# Consolidated Mailbag Deployment Script
# This script handles the complete deployment workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Starting Mailbag deployment from $SCRIPT_DIR"

# Color output for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [ ! -f "/etc/mailbag/context.json" ]; then
        log_error "/etc/mailbag/context.json not found!"
        log_error "Please run ./generate-context.sh first to create the configuration"
        exit 1
    fi

    # Validate context.json
    if ! jq . /etc/mailbag/context.json > /dev/null 2>&1; then
        log_error "Invalid JSON in /etc/mailbag/context.json"
        exit 1
    fi

    # The renderer version comes from the host's context.
    RENDERER=$("$SCRIPT_DIR/scripts/fetch-renderer.sh" /etc/mailbag/context.json)
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Step 1: Deploy to Kubernetes. There is no host preparation step: the
# workloads create their host_paths directories and set owner and mode
# themselves (PROJ-011).
deploy_kubernetes() {
    log_info "Step 1: Deploying to Kubernetes..."
    
    cd "$SCRIPT_DIR/deployment/k8s"
    
    # Run the deployment script
    if [ "$EUID" -eq 0 ]; then
        ./deploy-services.sh
    else
        log_warn "Running Kubernetes deployment with sudo"
        sudo ./deploy-services.sh
    fi
    
    log_info "Kubernetes deployment completed"
}

# Step 2: Check deployment status
check_status() {
    log_info "Step 2: Checking deployment status..."

    NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)

    echo "Services:"
    kubectl get services -n $NAMESPACE
    
    echo -e "\nPods:"
    kubectl get pods -n $NAMESPACE
    
    echo -e "\nPod status summary:"
    READY_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | grep -c "1/1.*Running" || echo "0")
    TOTAL_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | wc -l)
    
    if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
        log_info "All $TOTAL_PODS pods are running successfully!"
    else
        log_warn "$READY_PODS/$TOTAL_PODS pods are ready"
        
        if [ "$TOTAL_PODS" -gt 0 ]; then
            echo -e "\nChecking pod issues:"
            kubectl get pods -n $NAMESPACE --no-headers | grep -v "1/1.*Running" | while read line; do
                POD_NAME=$(echo $line | awk '{print $1}')
                echo "Describing pod $POD_NAME:"
                kubectl describe pod -n $NAMESPACE $POD_NAME | grep -A 10 "Events:"
            done
        fi
    fi
}

# Step 3: Show next steps
show_next_steps() {
    log_info "Step 3: Next steps for completion..."
    
    NAMESPACE=$(jq -r '.services.k8s_namespace' /etc/mailbag/context.json)
    DOMAIN=$(jq -r '.domain.zone' /etc/mailbag/context.json)
    
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Domain: $DOMAIN"
    echo "Namespace: $NAMESPACE"
    echo ""
    echo "Next steps to complete your mail server:"
    echo ""
    echo "1. Certificates follow tls.source in the context:"
    echo "   - cert-manager: Let's Encrypt over DNS-01 in Route53, once"
    echo "     secret/route53-credentials exists in the cert-manager namespace"
    echo "   - secret: courier-mail-cert-tls, created by hand"
    echo ""
    echo "2. DNS Configuration:"
    echo "   - Create A records for:"
    echo "     * $(jq -r '.mta.dns_name' /etc/mailbag/context.json)"
    echo "     * $(jq -r '.imapd_ssl.dns_name' /etc/mailbag/context.json)"
    echo "     * $(jq -r '.mta_ssl.dns_name' /etc/mailbag/context.json)"
    echo "     * $(jq -r '.msa.dns_name' /etc/mailbag/context.json)"
    echo "   - Create MX record pointing to $(jq -r '.mta.dns_name' /etc/mailbag/context.json)"
    echo ""
    echo "3. Mail Users:"
    echo "   - Declare them in the context's mailboxes, set each password with"
    echo "     scripts/mailbox-passwd.sh <address>, then rerun deployment/k8s/deploy-services.sh"
    echo ""
    echo "4. Testing (goss, pinned in context.json; run from the repo root):"
    echo "   - GOSS=\$(scripts/fetch-goss.sh /etc/mailbag/context.json)"
    echo "   - \$GOSS -g goss/host-k3s.yaml --vars /etc/mailbag/context.json validate"
    echo "   - scripts/node-test.sh <image tag>   (deploys the tag, then every host suite)"
    echo ""
    echo "=== TROUBLESHOOTING ==="
    echo "View logs: kubectl logs -n $NAMESPACE <pod-name>"
    echo "Check status: kubectl get pods,services -n $NAMESPACE"
    echo ""
}

# Main execution
main() {
    echo "============================================"
    echo "         Mailbag Deployment Script"
    echo "============================================"
    echo ""
    
    check_prerequisites
    deploy_kubernetes
    check_status
    show_next_steps
    
    log_info "Deployment script completed!"
}

# Parse command line arguments
case "${1:-}" in
    "check")
        check_status
        ;;
    "status")
        check_status
        ;;
    *)
        main
        ;;
esac