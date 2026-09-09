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
    letsencrypt-clusterissuer.yaml
    mail-certificates.yaml.template
    storage.yaml
    courierd.yaml
    courier-mta.yaml
    courier-mta-ssl.yaml
    courier-imapd-ssl.yaml
    courier-msa.yaml
)

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
            "$RENDERER" --context "$CONTEXT" --template "$path" > "$tmp"
            kubectl apply -f "$tmp"
            ;;
        *)
            echo "Applying $manifest ..."
            kubectl apply -f "$path"
            ;;
    esac
}

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
