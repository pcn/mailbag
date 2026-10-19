#!/bin/bash
# PROJ-011: every workload takes its host directories from host_paths.
# Run by goss/repo.yaml.
#
# Renders each workload template against the example context with host_paths
# replaced by distinctive values, so a path hardcoded in a template cannot
# pass by coinciding with the example. Then, per rendered Deployment or Job:
# every hostPath volume is the context file or one of the host_paths, the
# host_paths ones are DirectoryOrCreate, and the workload mounts exactly the
# ones expected of it.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

RENDERER=$(scripts/fetch-renderer.sh examples/example-context.json) || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

jq '.host_paths = {spool: "/check/spool", mail: "/check/mail",
                   courier_config: "/check/courier-config", authlib: "/check/authlib"}' \
    examples/example-context.json > "$work/context.json"

fail=0
# template | host paths it must mount, space separated
while IFS='|' read -r template want; do
    [ -n "$template" ] || continue
    if ! "$RENDERER" --strict -n "deployment/k8s/$template" "$work/context.json" > "$work/out.yaml" 2> "$work/err"; then
        echo "FAIL  $template does not render:"; sed 's/^/        /' "$work/err"
        fail=1
        continue
    fi
    if python3 -I - "$work/out.yaml" "$want" <<'PY'
import sys, yaml
rendered, want = sys.argv[1], set(sys.argv[2].split())
allowed = {"/check/spool", "/check/mail", "/check/courier-config", "/check/authlib"}
problems, used = [], set()
for doc in yaml.safe_load_all(open(rendered)):
    if not doc or doc.get("kind") not in ("Deployment", "Job"):
        continue
    for v in doc["spec"]["template"]["spec"].get("volumes", []):
        if "persistentVolumeClaim" in v:
            problems.append(f"volume {v['name']} is a PersistentVolumeClaim")
        hp = v.get("hostPath")
        if not hp or hp["path"] == "/etc/mailbag/context.json":
            continue
        if hp["path"] not in allowed:
            problems.append(f"volume {v['name']} hostPath {hp['path']} is not from host_paths")
        elif hp.get("type") != "DirectoryOrCreate":
            problems.append(f"volume {v['name']} is type {hp.get('type')}, not DirectoryOrCreate")
        used.add(hp["path"])
if used != want:
    problems.append(f"mounts {sorted(used)}, expected {sorted(want)}")
for p in problems:
    print("        " + p)
sys.exit(1 if problems else 0)
PY
    then
        echo "ok    $template mounts its host_paths as DirectoryOrCreate"
    else
        echo "FAIL  $template (above)"
        fail=1
    fi
done <<'EOF'
courier-mta.yaml.template|/check/spool /check/mail
courier-msa.yaml.template|/check/spool /check/mail
courier-mta-ssl.yaml.template|/check/spool /check/mail
courier-imapd-ssl.yaml.template|/check/spool /check/mail
courierd.yaml.template|/check/spool /check/mail
build-dat-job.yaml.template|/check/courier-config /check/authlib
EOF

exit "$fail"
