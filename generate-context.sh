#!/bin/bash
# Generate /etc/mailbag/context.json for a k3s mailbag host from a few answers.
# The result must satisfy cue/schema.cue's #Context; goss/repo.yaml checks that
# this script's defaults do (goss/lib/check-generated-contexts.sh).

set -e

# Where to write. Overridable so goss/repo.yaml can run this script for real,
# with every prompt answered by its default, without touching /etc/mailbag.
CONTEXT_OUT="${CONTEXT_OUT:-/etc/mailbag/context.json}"

# Default values
DOMAIN="example.com"
MAIL_HOSTNAME="mail"
IMAP_HOSTNAME="imap"
SMTP_HOSTNAME="smtp"
# Host directories (host_paths): the workloads create them if missing and set
# their owner and mode, so nothing prepares the host beforehand.
MAILBAG_SPOOL="/home/mailbag/spool/courier-mta"
MAIL_STORAGE="/home/vmail"
CONFIG_PATH="/home/mailbag/config"
# Which published build to deploy. Override per-deploy with IMAGE_TAG=... on
# deploy-services.sh; a sha-<sha> tag names an exact build and rolls back cleanly.
IMAGE_TAG="${IMAGE_TAG:-main}"
# Where the mail certificate comes from: cert-manager issues it from Let's
# Encrypt over DNS-01 in a Route53 zone, or "secret" for a host whose Secret is
# injected by hand (scripts/make-test-cert.sh). For cert-manager,
# ACME_HOSTED_ZONE_ID is required -- it cannot be guessed -- ACME_ZONE defaults
# to the mail domain, and ACME_EMAIL to letsencrypt@<domain>, the convention on
# every install so the Let's Encrypt account is never tied to a person or role.
TLS_SOURCE="${TLS_SOURCE:-cert-manager}"
# userdb.canary must be an account that exists in the userdb: the database
# build checks it resolves. It cannot be guessed, so the default is a
# placeholder that fails that check loudly until CANARY names a real account.
# POSTMASTER is "reject" or the address postmaster and role mail go to.
# Host layer below Kubernetes, checked by goss/host-k3s.yaml. data_dir belongs
# on the large filesystem, not a small /var (PROJ-024).
K3S_VERSION="${K3S_VERSION:-v1.32.5+k3s1}"
K3S_DATA_DIR="${K3S_DATA_DIR:-/home/k3s}"
K3S_GOMEMLIMIT="${K3S_GOMEMLIMIT:-300MiB}"
MIN_FREE_MB_DATA_DIR="${MIN_FREE_MB_DATA_DIR:-2048}"
MIN_FREE_MB_VAR="${MIN_FREE_MB_VAR:-1024}"

# Helper function to clean up hostname input
clean_hostname() {
    local hostname="$1"
    local domain="$2"

    # If hostname already contains the domain, use it as-is
    if [[ "$hostname" == *"$domain"* ]]; then
        echo "$hostname"
    else
        # Otherwise, append the domain
        echo "$hostname.$domain"
    fi
}

# Get user input
read -p "Enter your mail domain (default: $DOMAIN): " input
DOMAIN=${input:-$DOMAIN}

read -p "Enter mail hostname prefix or FQDN (default: $MAIL_HOSTNAME): " input
MAIL_HOSTNAME_INPUT=${input:-$MAIL_HOSTNAME}

read -p "Enter IMAP hostname prefix or FQDN (default: $IMAP_HOSTNAME): " input
IMAP_HOSTNAME_INPUT=${input:-$IMAP_HOSTNAME}

read -p "Enter SMTP hostname prefix or FQDN (default: $SMTP_HOSTNAME): " input
SMTP_HOSTNAME_INPUT=${input:-$SMTP_HOSTNAME}

read -p "Enter path for mail storage (default: $MAIL_STORAGE): " input
MAIL_STORAGE=${input:-$MAIL_STORAGE}

read -p "Enter path for courier spool (default: $MAILBAG_SPOOL): " input
MAILBAG_SPOOL=${input:-$MAILBAG_SPOOL}

# Clean up hostnames
MAIL_HOSTNAME=$(clean_hostname "$MAIL_HOSTNAME_INPUT" "$DOMAIN")
IMAP_HOSTNAME=$(clean_hostname "$IMAP_HOSTNAME_INPUT" "$DOMAIN")
SMTP_HOSTNAME=$(clean_hostname "$SMTP_HOSTNAME_INPUT" "$DOMAIN")

# ACME settings exist only for cert-manager; the schema refuses them for "secret".
if [ "$TLS_SOURCE" = cert-manager ]; then
    if [ -z "${ACME_HOSTED_ZONE_ID:-}" ]; then
        echo "ERROR: TLS_SOURCE=cert-manager needs ACME_HOSTED_ZONE_ID, the Route53 hosted zone" >&2
        echo "       id (Z...) the DNS-01 challenge records are written to." >&2
        exit 1
    fi
    TLS_BLOCK=$(jq -n --arg email "${ACME_EMAIL:-letsencrypt@$DOMAIN}" \
        --arg zone "${ACME_ZONE:-$DOMAIN}" --arg id "$ACME_HOSTED_ZONE_ID" \
        '{source: "cert-manager", acme: {email: $email, route53: {zone: $zone, hosted_zone_id: $id}}}')
else
    TLS_BLOCK="{\"source\": \"$TLS_SOURCE\"}"
fi

# Create output directory
mkdir -p "$(dirname "$CONTEXT_OUT")"

# Generate context.json
cat > "$CONTEXT_OUT" << EOF
{
  "host_paths": {
    "spool": "$MAILBAG_SPOOL",
    "mail": "$MAIL_STORAGE",
    "courier_config": "$CONFIG_PATH/courier",
    "authlib": "$CONFIG_PATH/authlib"
  },
  "mta": {
    "dns_name": "$DOMAIN",
    "accept_mail_for": ["$DOMAIN"]
  },
  "imapd_ssl": {
    "dns_name": "$IMAP_HOSTNAME"
  },
  "mta_ssl": {
    "dns_name": "$SMTP_HOSTNAME"
  },
  "msa": {
    "dns_name": "$MAIL_HOSTNAME"
  },
  "userdb": {
    "canary": "${CANARY:-CHANGE-ME@$DOMAIN}"
  },
  "aliases": {
    "postmaster": "${POSTMASTER:-reject}"
  },
  "domain": {
    "zone": "$DOMAIN"
  },
  "image": {
    "tag": "$IMAGE_TAG"
  },
  "services": {
    "smtp_port": 25,
    "smtps_port": 465,
    "submission_port": 587,
    "imaps_port": 993,
    "k8s_namespace": "mailbag"
  },
  "tls": $TLS_BLOCK,
  "host": {
    "k3s": {
      "version": "$K3S_VERSION",
      "data_dir": "$K3S_DATA_DIR",
      "gomemlimit": "$K3S_GOMEMLIMIT",
      "disable": ["traefik", "metrics-server", "local-storage"]
    },
    "min_free_mb": {
      "data_dir": $MIN_FREE_MB_DATA_DIR,
      "var": $MIN_FREE_MB_VAR
    }
  }
}
EOF

# Tool pins (renderer, goss, cue: versions and checksums) are copied from the
# example context rather than written here, so the repo pins them in one place.
EXAMPLE_CONTEXT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/examples/example-context.json"
tmp=$(mktemp)
jq --slurpfile ex "$EXAMPLE_CONTEXT" '.tools = $ex[0].tools' "$CONTEXT_OUT" > "$tmp"
mv "$tmp" "$CONTEXT_OUT"

echo "Generated context.json at $CONTEXT_OUT"
echo "Next: deployment/k8s/deploy-services.sh (it creates the host_paths directories itself)"
