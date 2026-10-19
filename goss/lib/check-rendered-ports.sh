#!/bin/bash
# Render the courier configs and the service manifests against the example
# context with every mail port moved to a non-standard number, then assert each
# port lands everywhere its service uses it -- the courier config, the
# containerPort, the Service and both probes -- and that no standard port
# number is left anywhere. Run by goss/repo.yaml.
#
# A port that is still hardcoded somewhere keeps its standard number here and
# fails. So does a probe whose arguments run together ("--port 993--expect"),
# which rendered cleanly and would have failed every readiness check.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

R=$(scripts/fetch-renderer.sh examples/example-context.json) || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

jq '.services.smtp_port = 2525
  | .services.smtps_port = 4465
  | .services.submission_port = 5587
  | .services.imaps_port = 5993' examples/example-context.json > "$work/ctx.json"

mkdir "$work/cm"
python3 -I - deployment/k8s/configmap.yaml "$work/cm" <<'PYEOF'
import pathlib, sys, yaml
out = pathlib.Path(sys.argv[2])
for doc in yaml.safe_load_all(pathlib.Path(sys.argv[1]).read_text()):
    for name, body in ((doc or {}).get("data") or {}).items():
        if name.endswith(".template"):
            (out / name).write_text(body)
PYEOF

fail=0
check() { # description, file, extended regex, expected match count
    local n
    n=$(grep -cE "$3" "$2")
    if [ "$n" -eq "$4" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1 (expected $4 match(es) of /$3/ in $(basename "$2"), found $n)"
        fail=1
    fi
}

# service  port  courier-config-template  key
while read -r svc port tmpl key; do
    "$R" --strict -n "$work/cm/$tmpl.template" "$work/ctx.json" > "$work/$tmpl.conf" || { echo "FAIL  render $tmpl"; fail=1; continue; }
    "$R" --strict -n "deployment/k8s/courier-$svc.yaml.template" "$work/ctx.json" > "$work/$svc.yaml" || { echo "FAIL  render courier-$svc"; fail=1; continue; }
    check "$svc: courier $key is $port"        "$work/$tmpl.conf" "^$key=$port\$" 1
    check "$svc: containerPort is $port"        "$work/$svc.yaml"  "containerPort: $port\$" 1
    check "$svc: Service port is $port"         "$work/$svc.yaml"  "^  - port: $port\$" 1
    check "$svc: both probes use --port $port"  "$work/$svc.yaml"  "mailbag-probe --port $port --" 2
done <<'EOF'
mta        2525  esmtpd-mta      PORT
msa        5587  esmtpd-msa      PORT
mta-ssl    4465  esmtpd-mta-ssl  SSLPORT
imapd-ssl  5993  imapd-ssl       SSLPORT
EOF

leftover=$(grep -nE '(PORT=|containerPort: |- port: |--port )(25|465|587|993)\b|PORT=smtp' "$work"/*.conf "$work"/*.yaml)
if [ -n "$leftover" ]; then
    echo "FAIL  standard port numbers remain:"; echo "$leftover" | sed "s#$work/#    #"
    fail=1
else
    echo "ok    no standard port number remains in any rendered config or manifest"
fi

exit "$fail"