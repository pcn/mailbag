#!/bin/bash
# Deploy mailbag to a Kubernetes cluster.
#
# Resources are applied in dependency order. Two kinds of input:
#
#   *.yaml           applied verbatim with kubectl.
#   *.yaml.template  rendered with render-template against context.json first.
#
# The distinction matters: configmap.yaml carries the courier config templates
# as data, full of Jinja that the container entrypoints render at runtime
# against their own context. Passing it through render-template would evaluate
# that Jinja here and ship pre-rendered files, breaking per-service rendering.
# So only files explicitly named *.yaml.template are rendered.

set -e -u -o pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="${CONTEXT:-/etc/mailbag/context.json}"
RENDERER="$REPO_ROOT/render-template"

if [ ! -f "$CONTEXT" ]; then
    echo "ERROR: $CONTEXT not found. Run generate-context.sh first." >&2
    exit 1
fi
if [ ! -x "$RENDERER" ]; then
    echo "ERROR: $RENDERER not found or not executable. Run 'make render-template'." >&2
    exit 1
fi

# Deploy a specific build: IMAGE_TAG=sha-<sha> ./deploy-services.sh
# Rolling back is the same command with an earlier tag. Without it, the tag
# comes from .image.tag in context.json, defaulting to main.
if [ -n "${IMAGE_TAG:-}" ]; then
    RENDER_CONTEXT=$(mktemp)
    trap 'rm -f "$RENDER_CONTEXT"' EXIT
    jq --arg t "$IMAGE_TAG" '.image = (.image // {}) | .image.tag = $t' \
        "$CONTEXT" > "$RENDER_CONTEXT"
    echo "Deploying image tag: $IMAGE_TAG"
else
    RENDER_CONTEXT="$CONTEXT"
    echo "Deploying image tag: $(jq -r '.image.tag // "main"' "$CONTEXT")"
fi

NAMESPACE=$(jq -r '.services.k8s_namespace' "$CONTEXT")
if [ -z "$NAMESPACE" ] || [ "$NAMESPACE" = "null" ]; then
    echo "ERROR: .services.k8s_namespace is missing from $CONTEXT" >&2
    exit 1
fi

# Applied in order. A missing entry is a hard error rather than a skip: the
# previous version silently skipped storage whenever one PVC happened to exist,
# which hid partial state and made a half-deployed cluster look successful.
MANIFESTS=(
    namespace.yaml
    configmap.yaml
    storage.yaml
    courierd.yaml.template
    courier-mta.yaml.template
    courier-mta-ssl.yaml.template
    courier-imapd-ssl.yaml.template
    courier-msa.yaml.template
)

# Certificates come from one of two places and the deploy must not guess.
#
#   cert-manager present -> apply the issuer and Certificate and let it fill
#                           the Secret in.
#   cert-manager absent  -> the Secret must already exist, injected by hand or
#                           by CI from a locally generated CA. This is the
#                           documented path for test nodes, where ACME cannot
#                           run at all: issuing a real certificate needs a DNS
#                           write, and neither CI nor the node is permitted
#                           credentials for the zone.
#
# Applying the Certificate without cert-manager would "succeed" and then never
# reconcile, leaving every pod stuck in ContainerCreating on a Secret that is
# never created. Refuse instead.
CERT_MANIFESTS=(
    letsencrypt-clusterissuer.yaml
    mail-certificates.yaml.template
)
CERT_SECRET=courier-mail-cert-tls

apply_one() {
    local manifest="$1"
    local path="$HERE/$manifest"

    if [ ! -f "$path" ]; then
        echo "ERROR: required manifest $manifest is missing" >&2
        return 1
    fi

    case "$manifest" in
        *.yaml.template)
            echo "Rendering and applying $manifest ..."
            local tmp
            tmp=$(mktemp)
            # shellcheck disable=SC2064
            trap "rm -f '$tmp'" RETURN
            "$RENDERER" --context "$RENDER_CONTEXT" --template "$path" > "$tmp"
            kubectl apply -f "$tmp"
            ;;
        *)
            echo "Applying $manifest ..."
            kubectl apply -f "$path"
            ;;
    esac
}

if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
    echo "cert-manager detected: applying issuer and Certificate."
    for manifest in "${CERT_MANIFESTS[@]}"; do
        apply_one "$manifest"
    done
else
    echo "cert-manager not installed: skipping issuer and Certificate."
    if kubectl -n "$NAMESPACE" get secret "$CERT_SECRET" >/dev/null 2>&1; then
        echo "  using the pre-existing $CERT_SECRET secret."
    else
        cat >&2 <<EOF
ERROR: cert-manager is not installed and secret/$CERT_SECRET does not exist in
namespace $NAMESPACE.

Every mail service mounts that Secret, so the pods would sit in
ContainerCreating forever. Provide it before deploying, either by installing
cert-manager or by injecting a certificate:

  kubectl -n $NAMESPACE create secret tls $CERT_SECRET \\
      --cert=/path/to/fullchain.pem --key=/path/to/privkey.pem

scripts/make-test-cert.sh generates a self-signed CA and server certificate
with the SANs taken from context.json, for test nodes.
EOF
        exit 1
    fi
fi

for manifest in "${MANIFESTS[@]}"; do
    apply_one "$manifest"
done

echo
echo "All resources applied to namespace $NAMESPACE."
echo
echo "Certificates are issued asynchronously by cert-manager. Check with:"
echo "  kubectl get certificate,certificaterequest,order,challenge -n $NAMESPACE"
echo
echo "Pods stay in ContainerCreating until the certificate Secret exists."
echo
echo "Verify the deployed image tags with:"
echo "  kubectl get pods -n $NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.spec.containers[*].image}{\"\\n\"}{end}'"
