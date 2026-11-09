#!/bin/bash
# PROJ-027: host setup installs cert-manager from the manifest the context
# pins, and never applies one whose sha256 differs. Run by goss/repo.yaml.
#
#  1. The pin (host.cert_manager) is declared in exactly one tracked file,
#     examples/example-context.json; no other file names a cert-manager
#     release URL with a literal version. The install step built from the
#     example context fetches that version's URL and checks that sha256.
#  2. The install step, run with curl and kubectl replaced by shims:
#     - a manifest whose sha256 differs from the pin: exits non-zero, and
#       kubectl is never called (the cluster is not contacted);
#     - a manifest that matches: applied with kubectl apply --server-side,
#       then waited on.
#
# The step comes from #Plan itself: a fixture file in a scratch copy of cue/
# builds a plan for a host already in sync except for cert-manager, so its
# script holds only the cert-manager steps.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

EXAMPLE=examples/example-context.json
CUE=$(scripts/fetch-cue.sh "$EXAMPLE") || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }

pin_version=$(jq -er '.host.cert_manager.version' "$EXAMPLE") || { bad "no host.cert_manager.version in $EXAMPLE"; exit 1; }
pin_sha=$(jq -er '.host.cert_manager.manifest_sha256' "$EXAMPLE") || { bad "no host.cert_manager.manifest_sha256 in $EXAMPLE"; exit 1; }

# 1. One declaration.
mapfile -t with_sha < <(git ls-files -z | xargs -0 grep -lF "$pin_sha" 2>/dev/null)
if [ "${with_sha[*]}" = "$EXAMPLE" ]; then
    ok "the manifest sha256 is declared only in $EXAMPLE"
else
    bad "the manifest sha256 appears in: ${with_sha[*]:-nothing}"
fi
mapfile -t with_url < <(git ls-files -z | xargs -0 grep -lE 'cert-manager/releases/download/v[0-9]' 2>/dev/null)
if [ ${#with_url[@]} -eq 0 ]; then
    ok "no file names a cert-manager release URL with a literal version"
else
    bad "a literal cert-manager release URL in: ${with_url[*]}"
fi

# script_for SHA: the plan's script for the example host, cert-manager
# missing, with the manifest pin replaced by SHA.
script_for() {
    rm -rf "$work/m"; mkdir -p "$work/m"; cp -r cue "$work/m/"
    {
        echo 'package mailbag'
        echo "_fixtureHost: $(jq --arg s "$1" '.host | .cert_manager.manifest_sha256 = $s' "$EXAMPLE")"
        cat <<'EOF'
_fixtureWant: #Desired & {in: _fixtureHost}
fixtureScript: (#Plan & {
	host:      _fixtureHost
	tlsSource: "cert-manager"
	have: {
		config:           _fixtureWant.config
		dropin:           _fixtureWant.dropin
		env:              _fixtureWant.envLine + "\n"
		k3sVersion:       "k3s version \(_fixtureHost.k3s.version) (fixture)\n"
		oldDataDir:       false
		certManagerImage: ""
	}
}).script
EOF
    } > "$work/m/cue/zz_fixture.cue"
    (cd "$work/m" && "$CUE" export ./cue -e fixtureScript --out text)
}

if s=$(script_for "$pin_sha" 2>"$work/err"); then
    if grep -qF "releases/download/$pin_version/cert-manager.yaml" <<<"$s" && grep -qF "$pin_sha" <<<"$s"; then
        ok "the install step fetches $pin_version's manifest and checks the pinned sha256"
    else
        bad "the install step does not use the pinned version and sha256:"; sed 's/^/        /' <<<"$s"
    fi
    if grep -qE 'systemctl|INSTALL_K3S' <<<"$s"; then
        bad "the fixture plan touches k3s, so the shim runs would not isolate cert-manager"
    fi
else
    bad "could not build the install step:"; sed 's/^/        /' "$work/err"
    exit 1
fi

# 2. Run the step with shims. curl writes the fixture manifest wherever -o
# says; kubectl records its arguments and succeeds.
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >> "$SHIM_LOG"
while [ $# -gt 0 ]; do
    case "$1" in -o) out=$2; shift ;; esac
    shift
done
cp "$FIXTURE" "$out"
EOF
cat > "$work/bin/kubectl" <<'EOF'
#!/bin/sh
echo "kubectl $*" >> "$SHIM_LOG"
EOF
chmod +x "$work/bin/curl" "$work/bin/kubectl"
printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: cert-manager\n' > "$work/fixture.yaml"
fixture_sha=$(sha256sum "$work/fixture.yaml" | cut -d' ' -f1)

run_step() {  # script -> exit status; log in $work/log
    : > "$work/log"
    printf '%s\n' "$1" > "$work/step.sh"
    env PATH="$work/bin:$PATH" SHIM_LOG="$work/log" FIXTURE="$work/fixture.yaml" \
        sh "$work/step.sh" > "$work/out" 2>&1
}

# A manifest that does not match the pin.
if run_step "$(script_for "$pin_sha")"; then
    bad "a manifest with the wrong sha256 was accepted"
elif grep -q '^kubectl' "$work/log"; then
    bad "a manifest with the wrong sha256 failed, but only after contacting the cluster:"
    sed 's/^/        /' "$work/log"
elif ! grep -q '^curl' "$work/log"; then
    bad "the wrong-sha256 run failed before downloading anything (not the check that refused it):"
    sed 's/^/        /' "$work/out"
else
    ok "a manifest with the wrong sha256 exits non-zero without contacting the cluster"
fi

# A manifest that matches.
if run_step "$(script_for "$fixture_sha")" \
        && grep -q '^kubectl apply --server-side -f .*/cert-manager.yaml$' "$work/log" \
        && [ "$(grep -c '^kubectl -n cert-manager rollout status deploy/' "$work/log")" -eq 3 ]; then
    ok "a matching manifest is applied server-side and each deployment's rollout waited on"
else
    bad "a matching manifest was not applied as expected:"
    sed 's/^/        /' "$work/out" "$work/log"
fi

exit "$fail"
