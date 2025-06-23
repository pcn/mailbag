#!/bin/bash
# This script generates a context.json file based on user input

set -e

# Default values
DOMAIN="example.com"
MAIL_HOSTNAME="mail"
IMAP_HOSTNAME="imap"
SMTP_HOSTNAME="smtp"
MAILBAG_SPOOL="/home/mailbag/spool/courier"
MAIL_STORAGE="/vmail"
CERT_PATH="/etc/letsencrypt/live"
CONFIG_PATH="/home/mailbag/config"
MAIL_USER="vmail"
MAIL_USER_ID="300"
AUTHLIB_USER="daemon"

# Get user input
read -p "Enter your mail domain (default: $DOMAIN): " input
DOMAIN=${input:-$DOMAIN}

read -p "Enter mail hostname (default: $MAIL_HOSTNAME): " input
MAIL_HOSTNAME=${input:-$MAIL_HOSTNAME}

read -p "Enter IMAP hostname (default: $IMAP_HOSTNAME): " input
IMAP_HOSTNAME=${input:-$IMAP_HOSTNAME}

read -p "Enter SMTP hostname (default: $SMTP_HOSTNAME): " input
SMTP_HOSTNAME=${input:-$SMTP_HOSTNAME}

read -p "Enter path for mail storage (default: $MAIL_STORAGE): " input
MAIL_STORAGE=${input:-$MAIL_STORAGE}

read -p "Enter path for courier spool (default: $MAILBAG_SPOOL): " input
MAILBAG_SPOOL=${input:-$MAILBAG_SPOOL}

read -p "Enter path for certificates (default: $CERT_PATH): " input
CERT_PATH=${input:-$CERT_PATH}

# Create output directory
mkdir -p /etc/mailbag

# Generate context.json
cat > /etc/mailbag/context.json << EOF
{
  "mda": {
    "mail_path_host": "$MAIL_STORAGE/$DOMAIN",
    "mail_path_container": "/vmail/$DOMAIN",
    "owner": "$MAIL_USER_ID",
    "owner_name": "$MAIL_USER",
    "mode": "0755"
  },
  "mta": {
    "dns_name": "$MAIL_HOSTNAME.$DOMAIN",
    "tls_certfile": "$CERT_PATH/$DOMAIN/fullchain.pem",
    "tls_keyfile": "$CERT_PATH/$DOMAIN/privkey.pem",
    "service": "courier-mta",
    "accept_mail_for": ["$DOMAIN"],
    "courierd_path_host": "$MAILBAG_SPOOL",
    "courierd_path_container": "/var/spool/courier"
  },
  "imapd_ssl": {
    "dns_name": "$IMAP_HOSTNAME.$DOMAIN",
    "tls_certfile": "$CERT_PATH/$DOMAIN/fullchain.pem",
    "tls_keyfile": "$CERT_PATH/$DOMAIN/privkey.pem",
    "service": "courier-imapd-ssl"
  },
  "mta_ssl": {
    "dns_name": "$SMTP_HOSTNAME.$DOMAIN",
    "tls_certfile": "$CERT_PATH/$DOMAIN/fullchain.pem",
    "tls_keyfile": "$CERT_PATH/$DOMAIN/privkey.pem",
    "service": "courier-mta-ssl",
    "accept_mail_for": ["$DOMAIN"],
    "courierd_path_host": "$MAILBAG_SPOOL",
    "courierd_path_container": "/var/spool/courier"
  },
  "msa": {
    "dns_name": "$MAIL_HOSTNAME.$DOMAIN",
    "tls_certfile": "$CERT_PATH/$DOMAIN/fullchain.pem",
    "tls_keyfile": "$CERT_PATH/$DOMAIN/privkey.pem",
    "service": "courier-msa",
    "courierd_path_host": "$MAILBAG_SPOOL",
    "courierd_path_container": "/var/spool/courier"
  },
  "userdb": {
    "directory": "/etc/authlib/userdb",
    "owner": "$AUTHLIB_USER",
    "mode": "0700"
  },
  "domain": {
    "name": "$MAIL_HOSTNAME",
    "zone": "$DOMAIN"
  },
  "config": {
    "courier_path": "$CONFIG_PATH/courier",
    "courier_mode": "0755",
    "authlib_path": "$CONFIG_PATH/authlib",
    "authlib_mode": "0700"
  },
  "filesystem": {
    "base_storage_mode": "0755",
    "msgq_mode": "0750",
    "msgs_mode": "0750",
    "filters_mode": "0750",
    "allfilters_mode": "0750",
    "tmp_mode": "0770",
    "track_mode": "0755"
  },
  "services": {
    "smtp_port": 25,
    "submission_port": 587,
    "imaps_port": 993,
    "ssh_port": 22,
    "k8s_namespace": "mailbag",
    "k8s_services": ["mta", "mta-ssl", "imapd-ssl", "msa"],
    "k8s_pods": ["courier-mta", "courier-mta-ssl", "courier-imapd-ssl", "courier-msa", "courierd"]
  }
}
EOF

echo "Generated context.json at /etc/mailbag/context.json"
echo "Now run ./generate-host-scripts.sh to create the host preparation script"
