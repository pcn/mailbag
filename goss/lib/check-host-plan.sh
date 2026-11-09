#!/bin/bash
# Check the host-setup CUE (PROJ-026). Run by goss/repo.yaml.
#
#  1. The *_tool.cue files only orchestrate: outside comments and strings they
#     hold no comparison operator and no strings., list. or regexp. call, so
#     every decision lives in plain .cue where plan_tests.cue covers it.
#  2. The #Plan test cases pass (cue export -e tests).
#  3. The tests are not vacuous: on scratch copies, they fail when #EnvEdit
#     moves our /etc/environment line to the end, when an unchanged
#     drop-in is written anyway, when cert-manager is re-applied at the
#     deployed version, and when a logrotate rewrite restarts journald; and
#     check 1 fails on a tool file given a comparison.

set -u -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

CUE=$(scripts/fetch-cue.sh examples/example-context.json) || exit 1
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fail=0
ok()   { echo "ok    $*"; }
bad()  { echo "FAIL  $*"; fail=1; }

# Print the offending lines of a tool file, if any. Strips // comments,
# "..." strings and """ blocks first, so a ">" in a shell redirection or a
# word in a comment is not mistaken for logic.
impure() {
    awk '
        /^[[:space:]]*"""/ && inblock { inblock = 0; next }
        inblock { next }
        /"""[[:space:]]*$/ { inblock = 1; sub(/"""[[:space:]]*$/, "") }
        { print FILENAME ":" FNR ": " $0 }
    ' "$1" \
    | sed -E 's#//.*$##' \
    | sed -E 's/"([^"\\]|\\.)*"//g' \
    | grep -E '==|!=|<=|>=|=~|!~|[<>]|(^|[^A-Za-z_])(strings|list|regexp)\.'
}

# 1. Purity of the tool files.
tools=(cue/*_tool.cue)
[ -e "${tools[0]}" ] || { bad "no cue/*_tool.cue files found"; exit 1; }
for f in "${tools[@]}"; do
    if out=$(impure "$f"); then
        bad "$f holds logic that belongs in plain .cue:"; sed 's/^/        /' <<<"$out"
    else
        ok "$f only orchestrates"
    fi
done

# 2. The plan tests.
if "$CUE" export ./cue -e tests >/dev/null 2>"$work/err"; then
    ok "the #Plan test cases pass"
else
    bad "the #Plan test cases fail:"; sed 's/^/        /' "$work/err"
fi

# 3. Mutations on scratch copies: each must make its check fail.
mutant() {  # makes a fresh scratch copy of cue/ and prints its path
    rm -rf "$work/m"; mkdir -p "$work/m"; cp -r cue "$work/m/"; echo "$work/m/cue"
}
# cue refuses an absolute package path, so run from the copy's parent. The
# failure must be a test conflict (an error under tests.), not a mutant that
# no longer evaluates, or the check would pass vacuously.
expect_tests_fail() {  # name cue-dir
    if (cd "$(dirname "$2")" && "$CUE" export ./cue -e tests >/dev/null 2>"$work/merr"); then
        bad "the tests still pass when $1"
    elif grep -q '^tests\.' "$work/merr"; then
        ok "the tests fail when $1"
    else
        bad "the mutant for '$1' fails without reaching the tests:"; sed 's/^/        /' "$work/merr" | head -5
    fi
}

# 3a. #EnvEdit drops our line where it stands and appends it at the end.
m=$(mutant)
marker=$'\tif len(hits) > 0 {'
if grep -qF "$marker" "$m/desired.cue"; then
    python3 -I - "$m/desired.cue" <<'EOF'
import sys
p = sys.argv[1]
t = open(p).read()
i = t.index("\tif len(hits) > 0 {")
t = t[:i] + '''\tif len(hits) > 0 {
\t\tout: strings.Join(list.Concat([[for i, l in lines if !list.Contains(hits, i) && l != "" {l}], [line, ""]]), "\\n")
\t}
}
'''
open(p, "w").write(t)
EOF
    expect_tests_fail "#EnvEdit moves our line to the end" "$m"
else
    bad "mutation 3a: #EnvEdit no longer has the line it rewrites"
fi

# 3b. The drop-in counts as changed even when it matches.
m=$(mutant)
from='let dropinChanged = go && have.dropin != want.dropin'
if grep -qF "$from" "$m/plan.cue"; then
    sed -i "s/$from/let dropinChanged = go/" "$m/plan.cue"
    expect_tests_fail "an unchanged drop-in is written anyway" "$m"
else
    bad "mutation 3b: plan.cue no longer has the line it rewrites"
fi

# 3d. cert-manager is applied on every run, whatever version is deployed
#     (PROJ-027: a re-run at the same version must apply nothing).
m=$(mutant)
from='certManagerInstalled != want.certManager.version'
if grep -qF "$from" "$m/plan.cue"; then
    sed -i "s/$from/true/" "$m/plan.cue"
    expect_tests_fail "cert-manager is re-applied at the same version" "$m"
else
    bad "mutation 3d: plan.cue no longer has the line it rewrites"
fi

# 3e. A rewritten logrotate rule also restarts journald (PROJ-044: only the
#     journald drop-in needs a restart).
m=$(mutant)
from='restartJournald: journaldChanged'
if grep -qF "$from" "$m/plan.cue"; then
    sed -i "s/$from/restartJournald: journaldChanged || logrotateChanged/" "$m/plan.cue"
    expect_tests_fail "a logrotate rewrite restarts journald" "$m"
else
    bad "mutation 3e: plan.cue no longer has the line it rewrites"
fi

# 3c. A comparison in a tool file is caught by check 1.
m=$(mutant)
echo '_leak: len(_root) == 0' >> "$m/host_tool.cue"
if impure "$m/host_tool.cue" >/dev/null; then
    ok "the purity check catches a comparison in a tool file"
else
    bad "the purity check misses a comparison in a tool file"
fi

exit "$fail"
