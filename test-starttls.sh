#!/bin/bash
set -e -u -o pipefail

SMTPHOST=bust.spacey.org
set -x

# From https://www.saotn.org/test-smtp-authentication-starttls/
encoded=$(echo -ne "\0spacey@${SMTPHOST}\0password" | base64)

echo $encoded

echo openssl s_client -connect ${SMTPHOST}:25 -starttls smtp
