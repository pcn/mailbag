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
tls.source cert-manager with no issuer|.tls = {source: "cert-manager"}
tls.source secret that names an issuer|.tls = {source: "secret", issuer: "letsencrypt-staging"}
host.k3s.data_dir under /var|.host.k3s.data_dir = "/var/lib/rancher/k3s"
host.k3s.data_dir exactly /var|.host.k3s.data_dir = "/var"
an unknown top-level key|.extra = 1
a sha256 that is not 64 hex characters|.tools.goss.sha256["x86_64-unknown-linux-gnu"] = "abc123"
tools.cue missing|del(.tools.cue)
EOF

exit "$fail"
