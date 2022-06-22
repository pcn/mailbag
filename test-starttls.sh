#!/bin/bash
set -e -u -o pipefail

SMTPHOST=testmail.rton.me
set -x

# From https://www.saotn.org/test-smtp-authentication-starttls/
encoded=$(echo -ne "\0spacey@${SMTPHOST}\0test123" | base64)

echo $encoded

echo openssl s_client -connect ${SMTPHOST}:587 -starttls smtp
