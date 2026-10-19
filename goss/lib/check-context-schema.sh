#!/bin/bash
# Check cue/schema.cue's #Context against the example context: the example
# must be accepted, and every case below -- the example with one thing made
# wrong -- must be rejected. Run by goss/repo.yaml.
#
# The cases are built from the example with jq rather than stored as fixture
# files, so they cannot drift from it: each one differs from a valid context
# in exactly the way its name says.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

EXAMPLE=examples/example-context.json
CUE=$(scripts/fetch-cue.sh "$EXAMPLE") || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

vet() { "$CUE" vet -c -d '#Context' ./cue "$1" >"$work/err" 2>&1; }

fail=0
if vet "$EXAMPLE"; then
    echo "ok    the example context is accepted"
else
    echo "FAIL  the example context is rejected:"; sed 's/^/        /' "$work/err"
    fail=1
fi

# name | jq filter applied to the example
while IFS='|' read -r name filter; do
    [ -n "$name" ] || continue
    jq "$filter" "$EXAMPLE" > "$work/case.json"
    if vet "$work/case.json"; then
        echo "FAIL  accepted: $name"
        fail=1
    else
        echo "ok    rejected: $name"
    fi
done <<'EOF'
missing services.smtps_port|del(.services.smtps_port)
a port given as a string|.services.smtp_port = "25"
two services on one port|.services.smtps_port = .services.smtp_port
msa.port present|.msa.port = "smtp"
tls.source cert-manager with no acme settings|.tls = {source: "cert-manager"}
tls.source secret that carries acme settings|.tls = {source: "secret", acme: .tls.acme}
the removed tls.issuer key|.tls.issuer = "letsencrypt-staging"
a certificate name outside the Route53 zone|.mta_ssl.dns_name = "mail.elsewhere.org"
a zone that is only a suffix of a name, not its parent|.tls.acme.route53.zone = "domain.com"
a hosted zone id not in Route53's form|.tls.acme.route53.hosted_zone_id = "rton.me"
an acme email that is not an address|.tls.acme.email = "postmaster"
host.k3s.data_dir under /var|.host.k3s.data_dir = "/var/lib/rancher/k3s"
host.k3s.data_dir exactly /var|.host.k3s.data_dir = "/var"
an unknown top-level key|.extra = 1
a sha256 that is not 64 hex characters|.tools.goss.sha256["x86_64-unknown-linux-gnu"] = "abc123"
tools.cue missing|del(.tools.cue)
a removed systemd-era key: docker|.docker = {}
a removed systemd-era key: mta.service|.mta.service = "courier-mta.service"
a removed systemd-era key: mta.tls_certfile|.mta.tls_certfile = "/etc/letsencrypt/live/x/fullchain.pem"
a removed unread block: filesystem|.filesystem = {tmp_mode: "0770"}
a removed unread key: services.k8s_pods|.services.k8s_pods = ["courier-mta"]
EOF

exit "$fail"
