#!/bin/bash
# PROJ-036: a sha-<commit> service image contains that commit's packages and
# base, or does not exist. The services and config-completeness jobs must
# need packages and base, and their `if:` must be false whenever packages or
# base failed. Run by goss/repo.yaml.
#
# The conditions are evaluated, not pattern-matched: each is translated from
# GitHub's expression syntax (only !cancelled(), ==, !=, &&, || and
# parentheses appear) into Python and run over the upstream results below.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

WF=.github/workflows/build-and-publish.yml
command -v yq >/dev/null || { echo "FAIL  yq not found"; exit 1; }

fail=0
for job in services config-completeness; do
    needs=$(yq -r ".jobs.\"$job\".needs[]" "$WF" | tr '\n' ' ')
    for n in packages base; do
        case " $needs" in
            *" $n "*) echo "ok    $job needs $n" ;;
            *)        echo "FAIL  $job does not need $n (needs: $needs)"; fail=1 ;;
        esac
    done

    cond=$(yq -r ".jobs.\"$job\".if" "$WF")
    # expected | packages | base | services
    while IFS='|' read -r want p b s; do
        [ -n "$want" ] || continue
        got=$(python3 -I -c '
import re, sys
cond, p, b, s = sys.argv[1:]
r = {"packages": p, "base": b, "services": s, "changes": "success"}
e = cond.replace("!cancelled()", "True")
e = re.sub(r"needs\.([\w-]+)\.result", lambda m: repr(r[m.group(1)]), e)
e = e.replace("&&", " and ").replace("||", " or ")
e = re.sub(r"!(?!=)", " not ", e)
print("run" if eval(e, {"__builtins__": {}}) else "skip")
' "$cond" "$p" "$b" "$s") || { echo "FAIL  $job: cannot evaluate: $cond"; fail=1; break; }
        if [ "$got" = "$want" ]; then
            echo "ok    $job: packages=$p base=$b services=$s -> $got"
        else
            echo "FAIL  $job: packages=$p base=$b services=$s -> $got, want $want"
            fail=1
        fi
    done <<'EOF'
skip|failure|skipped|success
skip|success|failure|success
skip|cancelled|skipped|success
run|success|success|success
run|success|skipped|success
EOF
done

# config-completeness also must not run on a failed services build.
cond=$(yq -r '.jobs."config-completeness".if' "$WF")
case "$cond" in
    *"needs.services.result == 'success'"*) echo "ok    config-completeness requires services success" ;;
    *) echo "FAIL  config-completeness does not require services success"; fail=1 ;;
esac

exit "$fail"
