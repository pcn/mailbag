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

# Overridable so this can run from a copied tree rather than only a git
# checkout -- a deploy target may have neither the repository nor git.
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)")}"
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
# Applied through kustomize in phase 4, so that generator references are
# rewritten. namespace/configmap/storage go first, in phase 1, because the
# build job needs them.
MANIFESTS=(
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

# ---------------------------------------------------------------------------
# Phase 1: the resources the build job needs before it can run.
for manifest in namespace.yaml configmap.yaml storage.yaml; do
    apply_one "$manifest"
done

# ---------------------------------------------------------------------------
# Phase 2: build the derived databases out of band.
#
# Serving pods do not build these any more. The job renders the sources, builds
# all six, validates them -- including a canary lookup against both userdb
# databases, which is what catches a database that is valid and useless -- and
# publishes only if every check passes.
JOB_NAME="courier-build-dat-$(date +%s)"
echo
echo "Building courier databases (job/$JOB_NAME) ..."
BUILD_TMP=$(mktemp)
trap 'rm -f "$BUILD_TMP"' EXIT
"$RENDERER" --context "$RENDER_CONTEXT" --template "$HERE/build-dat-job.yaml.template" \
    | sed "s/^  name: courier-build-dat$/  name: $JOB_NAME/" > "$BUILD_TMP"
kubectl apply -f "$BUILD_TMP"

# backoffLimit is 0, so this settles either way rather than retrying.
if ! kubectl wait --for=condition=complete "job/$JOB_NAME" -n "$NAMESPACE" --timeout=300s 2>/dev/null; then
    echo >&2
    echo "ERROR: the database build did not complete. Its log:" >&2
    kubectl logs "job/$JOB_NAME" -n "$NAMESPACE" --tail=60 >&2 || true
    echo >&2
    echo "Nothing was published: the live databases are untouched and the running" >&2
    echo "pods are unaffected. Fix the input and re-run." >&2
    exit 1
fi
kubectl logs "job/$JOB_NAME" -n "$NAMESPACE" --tail=40 | sed 's/^/  /'

# ---------------------------------------------------------------------------
# Phase 3: collect the databases through the cluster.
#
# Deliberately not read off the hostPath directories the PVs happen to use.
# That works only when the deploy runs on the node itself, and the point of
# this project is to deploy to a node from somewhere else -- CI, or a
# workstation. Pulling them through the API server keeps that possible.
#
# The build job's pod has terminated by now, so a short-lived helper mounts the
# same volumes read-only and streams the files out.
DAT_DIR="$HERE/dat"
mkdir -p "$DAT_DIR"
HELPER="courier-dat-collect-$$"

cleanup_helper() { kubectl delete pod "$HELPER" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap 'rm -f "$BUILD_TMP"; cleanup_helper' EXIT

echo
echo "Collecting databases via pod/$HELPER ..."
kubectl apply -f - <<HELPER_POD >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $HELPER
  namespace: $NAMESPACE
  labels: {app: mailbag, component: dat-collect}
spec:
  restartPolicy: Never
  securityContext: {runAsUser: 0}
  containers:
  - name: collect
    image: busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
    command: ["sh", "-c", "sleep 300"]
    volumeMounts:
    - {name: courier-config, mountPath: /src/courier, readOnly: true}
    - {name: courier-auth, mountPath: /src/authlib, readOnly: true}
  volumes:
  - name: courier-config
    persistentVolumeClaim: {claimName: courier-config-pvc}
  - name: courier-auth
    persistentVolumeClaim: {claimName: courier-auth-pvc}
HELPER_POD

kubectl wait --for=condition=ready "pod/$HELPER" -n "$NAMESPACE" --timeout=120s >/dev/null \
    || { echo "ERROR: collection pod did not become ready" >&2; exit 1; }

kubectl exec -n "$NAMESPACE" "$HELPER" -- tar cf - \
    -C /src/courier hosteddomains.dat esmtpacceptmailfor.dat smtpaccess.dat aliases.dat \
    -C /src/authlib userdb.dat userdbshadow.dat \
    | tar xf - -C "$DAT_DIR" || { echo "ERROR: collecting the databases failed" >&2; exit 1; }
cleanup_helper

for f in hosteddomains.dat esmtpacceptmailfor.dat smtpaccess.dat aliases.dat \
         userdb.dat userdbshadow.dat; do
    [ -s "$DAT_DIR/$f" ] || { echo "ERROR: $f was not collected" >&2; exit 1; }
done
echo "Collected 6 databases into $DAT_DIR"

# ---------------------------------------------------------------------------
# Phase 4: apply the workloads with kustomize.
#
# The deployments have to go through kustomize too, not just the generators:
# configMapGenerator hashes the content into the object name, and only
# resources kustomize manages get their references rewritten to that name. That
# rewrite is the whole rollout mechanism -- changed databases change the pod
# template, so the pods roll and the new couriertcpd opens the new files.
# Applying the deployments separately would leave them pointing at a name that
# does not exist.
KUSTOMIZE_DIR=$(mktemp -d)
trap 'rm -f "$BUILD_TMP"; rm -rf "$KUSTOMIZE_DIR"; cleanup_helper' EXIT
mkdir -p "$KUSTOMIZE_DIR/dat"
cp "$DAT_DIR"/*.dat "$KUSTOMIZE_DIR/dat/"

RESOURCES=()
for manifest in "${MANIFESTS[@]}"; do
    out="$KUSTOMIZE_DIR/${manifest%.template}"
    case "$manifest" in
        *.yaml.template)
            "$RENDERER" --context "$RENDER_CONTEXT" --template "$HERE/$manifest" > "$out" ;;
        *) cp "$HERE/$manifest" "$out" ;;
    esac
    RESOURCES+=("${manifest%.template}")
done

{
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "namespace: $NAMESPACE"
    echo "resources:"
    for r in "${RESOURCES[@]}"; do echo "  - $r"; done
    echo "configMapGenerator:"
    echo "  - name: courier-dat"
    echo "    files:"
    for f in hosteddomains.dat esmtpacceptmailfor.dat smtpaccess.dat aliases.dat; do
        echo "      - dat/$f"
    done
    echo "secretGenerator:"
    echo "  - name: courier-userdb"
    echo "    files:"
    for f in userdb.dat userdbshadow.dat; do echo "      - dat/$f"; done
} > "$KUSTOMIZE_DIR/kustomization.yaml"

echo
echo "Generated object names (a change here is what rolls the pods):"
kubectl kustomize "$KUSTOMIZE_DIR" | grep -E "^  name: courier-(dat|userdb)-" | sed 's/^  name:/   /'
kubectl apply -k "$KUSTOMIZE_DIR"

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
