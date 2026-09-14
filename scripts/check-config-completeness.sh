#!/bin/bash
# Assert that every courier config we REPLACE still sets everything the shipped
# config set.
#
# The templates in deployment/k8s/configmap.yaml do not amend courier's config,
# they overwrite it. Anything a template omits is silently lost, and courier has
# no complaint to make about a setting that simply is not there. That is not
# hypothetical: the rendered /etc/courier/esmtpd carried 11 of the 32 settings
# in esmtpd.dist, and the missing PORT meant the start script invoked
#
#     couriertcpd $TCPDOPTS $PORT .../courieresmtpd
#
# with PORT empty, so courieresmtpd was eaten as the port argument and
# couriertcpd died on a usage error. Every service reported Running and listened
# on nothing, because the start script sends couriertcpd's stderr to /dev/null
# and exits 0 regardless.
#
# The fix is not to amend -- that drifts, in both directions. It is to keep full
# replacement and assert completeness against the .dist the image ships.
#
# The .dist files are read FROM THE IMAGE rather than from a checked-in copy.
# That is the half of the check that catches drift from courier: a version bump
# that introduces a setting fails here immediately, where a vendored fixture
# would quietly agree with itself forever.

set -u -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE="${IMAGE:-ghcr.io/pcn/mailbag/courier-mta:pr-79}"
CONTEXT="${CONTEXT:-examples/example-context.json}"
DIST_DIR="${DIST_DIR:-}"   # set to skip docker and use pre-extracted files

# template name in configmap.yaml : path of the .dist inside the image
MAPPING=(
    "esmtpd-base-mta.template:/etc/courier/esmtpd.dist"
    "esmtpd-base-msa.template:/etc/courier/esmtpd.dist"
    "esmtpd-base-mta-ssl.template:/etc/courier/esmtpd.dist"
    "esmtpd-mta.template:/etc/courier/esmtpd.dist"
    "esmtpd-msa.template:/etc/courier/esmtpd-msa.dist"
    "esmtpd-mta-ssl.template:/etc/courier/esmtpd-ssl.dist"
    "imapd-ssl.template:/etc/courier/imapd-ssl.dist"
)

# Not settings files: lists and access rules, with no .dist counterpart. Listed
# explicitly so that "not covered" is a decision rather than an oversight.
EXCLUDED=(
    "acceptmailfor.template"
    "hosteddomains.template"
    "smtpaccess-default.template"
    "authdaemonrc.template"
)

RENDERER="templater/target/debug/render-template"
[ -x "$RENDERER" ] || { echo "building $RENDERER ..."; (cd templater && cargo build --quiet) || exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- .dist files
if [ -n "$DIST_DIR" ]; then
    echo "Using pre-extracted .dist files from $DIST_DIR"
    cp "$DIST_DIR"/* "$WORK/" 2>/dev/null
else
    echo "Extracting .dist files from $IMAGE ..."
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        docker pull -q "$IMAGE" >/dev/null 2>&1 || { echo "ERROR: cannot pull $IMAGE" >&2; exit 1; }
    fi
    CID=$(docker create "$IMAGE") || { echo "ERROR: cannot create container from $IMAGE" >&2; exit 1; }
    for entry in "${MAPPING[@]}"; do
        dist="${entry##*:}"
        docker cp "$CID:$dist" "$WORK/$(basename "$dist")" 2>/dev/null
    done
    docker rm -f "$CID" >/dev/null 2>&1
fi

# ------------------------------------------------------- render the templates
# configmap.yaml carries the templates as ConfigMap data, so they have to be
# pulled out before they can be rendered.
python3 - "$WORK" <<'PYEOF'
import yaml, pathlib, sys
work = pathlib.Path(sys.argv[1])
cm = yaml.safe_load(pathlib.Path("deployment/k8s/configmap.yaml").read_text())
for name, body in cm["data"].items():
    if name.endswith(".template"):
        (work / name).write_text(body)
PYEOF

status=0
warnings=0

# Every settings-shaped template must be either mapped or explicitly excluded,
# so a new one cannot quietly escape the check.
echo
echo "=== coverage ==="
for f in "$WORK"/*.template; do
    name=$(basename "$f")
    assignments=$(grep -cE '^[A-Za-z_]+=' "$f" 2>/dev/null || echo 0)
    mapped=false
    for entry in "${MAPPING[@]}"; do [ "${entry%%:*}" = "$name" ] && mapped=true; done
    for x in "${EXCLUDED[@]}"; do [ "$x" = "$name" ] && mapped=true; done
    if ! $mapped; then
        if [ "$assignments" -gt 2 ]; then
            echo "  UNMAPPED  $name looks like a settings file ($assignments assignments) but has no .dist mapping"
            status=1
        else
            echo "  note      $name is unmapped and not settings-shaped ($assignments assignments)"
        fi
    fi
done
[ "$status" -eq 0 ] && echo "  all settings templates are mapped or explicitly excluded"

# ------------------------------------------------------------------ the check
echo
echo "=== completeness ==="
for entry in "${MAPPING[@]}"; do
    name="${entry%%:*}"
    dist_path="${entry##*:}"
    dist_file="$WORK/$(basename "$dist_path")"
    tmpl="$WORK/$name"

    if [ ! -f "$tmpl" ]; then
        echo "  FAIL  $name -- not present in configmap.yaml"; status=1; continue
    fi
    if [ ! -f "$dist_file" ]; then
        echo "  FAIL  $name -- cannot read $dist_path from the image"; status=1; continue
    fi

    rendered="$WORK/$name.rendered"
    if ! "$RENDERER" --context "$CONTEXT" --template "$tmpl" > "$rendered" 2>"$WORK/err"; then
        echo "  FAIL  $name -- does not render:"; sed 's/^/          /' "$WORK/err"; status=1; continue
    fi

    # Only uncommented assignments are required. A commented default in .dist
    # means "unset, use the built-in", so omitting it is equivalent.
    grep -oE '^[A-Z][A-Z0-9_]*=' "$dist_file" | tr -d '=' | sort -u > "$WORK/required"
    grep -oE '^[A-Z][A-Z0-9_]*=' "$rendered"  | tr -d '=' | sort -u > "$WORK/provided"

    missing=$(comm -23 "$WORK/required" "$WORK/provided" | tr '\n' ' ')
    extra=$(comm -13 "$WORK/required" "$WORK/provided" | tr '\n' ' ')

    if [ -n "${missing// /}" ]; then
        echo "  FAIL  $name vs $(basename "$dist_path")"
        echo "          missing: $missing"
        status=1
    else
        echo "  ok    $name vs $(basename "$dist_path") ($(wc -l < "$WORK/required") settings covered)"
    fi
    # Extras are legitimate optional settings courier accepts but does not ship
    # a default for -- SYSLOGNAME and TLS_PROTOCOL among them. Never fatal.
    if [ -n "${extra// /}" ]; then
        echo "          note, not in .dist: $extra"
        warnings=$((warnings+1))
    fi
done

echo
if [ "$status" -ne 0 ]; then
    cat <<'EOF'
These templates REPLACE courier's config rather than amending it, so any
setting they omit is lost entirely. Add the missing settings to the template in
deployment/k8s/configmap.yaml, taking the value from the .dist unless there is
a reason to differ.
EOF
else
    echo "All replaced configs cover their .dist. ($warnings informational note(s).)"
fi
exit "$status"
