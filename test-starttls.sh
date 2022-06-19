#!/bin/bash
set -e -u -o pipefail
set -x 
# From https://www.saotn.org/test-smtp-authentication-starttls/
echo -ne '\0spacey@bust.spacey.org\0password' | base64

# openssl s_client -connect smtp.example.com:25 -starttls smtp
