#!/bin/bash
# Generate a self-signed CA and a server certificate for a test node, and
# optionally load it into Kubernetes as the Secret the mail services mount.
#
# This exists because a test node cannot obtain a real certificate. Both ACME
# challenge types need a DNS write against the zone -- DNS-01 needs the
# challenge TXT record, HTTP-01 needs an A record pointing at the node -- and
# neither CI nor the node is permitted credentials for that zone. So automated
# testing uses a CA generated here, and the test client is pointed at it.
#
# The SANs come from context.json rather than being passed in, so the
# certificate cannot drift from the hostnames the services are actually
# configured to answer on.

set -e -u -o pipefail

CONTEXT="${CONTEXT:-/etc/mailbag/context.json}"
OUTDIR="${OUTDIR:-./test-certs}"
DAYS="${DAYS:-365}"
NAMESPACE="${NAMESPACE:-}"
SECRET_NAME="${SECRET_NAME:-courier-mail-cert-tls}"

[ -f "$CONTEXT" ] || { echo "ERROR: $CONTEXT not found" >&2; exit 1; }
command -v openssl >/dev/null || { echo "ERROR: openssl not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq not found" >&2; exit 1; }

# Same four names mail-certificates.yaml.template puts on the real certificate.
# Deduplicated: a context can legitimately point several services at one host,
# and a repeated SAN is at best noise and at worst rejected.
mapfile -t SANS < <(jq -r '
    [ .domain.zone, .msa.dns_name, .mta_ssl.dns_name, .imapd_ssl.dns_name ]
    | map(select(. != null and . != ""))
    | unique
    | .[]' "$CONTEXT")

[ "${#SANS[@]}" -gt 0 ] || { echo "ERROR: no hostnames found in $CONTEXT" >&2; exit 1; }

CN=$(jq -r '.domain.zone' "$CONTEXT")
mkdir -p "$OUTDIR"

echo "Common name: $CN"
echo "SANs:"
printf '  %s\n' "${SANS[@]}"

SAN_LINE=$(printf 'DNS:%s,' "${SANS[@]}"); SAN_LINE="${SAN_LINE%,}"

echo
echo "Generating CA ..."
openssl req -x509 -newkey rsa:2048 -nodes -days "$DAYS" \
    -keyout "$OUTDIR/ca.key" -out "$OUTDIR/ca.crt" \
    -subj "/CN=mailbag test CA/O=mailbag" 2>/dev/null

echo "Generating server key and CSR ..."
openssl req -newkey rsa:2048 -nodes \
    -keyout "$OUTDIR/tls.key" -out "$OUTDIR/tls.csr" \
    -subj "/CN=$CN" -addext "subjectAltName=$SAN_LINE" 2>/dev/null

echo "Signing ..."
openssl x509 -req -in "$OUTDIR/tls.csr" -days "$DAYS" \
    -CA "$OUTDIR/ca.crt" -CAkey "$OUTDIR/ca.key" -CAcreateserial \
    -out "$OUTDIR/tls.crt" \
    -extfile <(printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\n' "$SAN_LINE") 2>/dev/null

rm -f "$OUTDIR/tls.csr" "$OUTDIR/ca.srl"
# The key is readable only by its owner here; in the cluster the Secret is
# projected 0440 with an fsGroup matching each service.
chmod 600 "$OUTDIR/ca.key" "$OUTDIR/tls.key"

echo
echo "Verifying the SANs actually landed on the certificate ..."
openssl x509 -in "$OUTDIR/tls.crt" -noout -ext subjectAltName | tail -1 | sed 's/^/  /'
openssl verify -CAfile "$OUTDIR/ca.crt" "$OUTDIR/tls.crt" | sed 's/^/  /'

echo
echo "Wrote:"
echo "  $OUTDIR/ca.crt   <- trust this in the test client"
echo "  $OUTDIR/tls.crt  $OUTDIR/tls.key"

if [ -n "$NAMESPACE" ]; then
    echo
    echo "Loading into namespace $NAMESPACE as secret/$SECRET_NAME ..."
    kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
        --cert="$OUTDIR/tls.crt" --key="$OUTDIR/tls.key" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "  done. The services read tls.crt and tls.key from this Secret."
else
    echo
    echo "To load it:  NAMESPACE=mailbag $0"
fi
