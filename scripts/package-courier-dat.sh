#!/bin/bash
#
# Package built .dat databases into a ConfigMap and a Secret, with a content
# checksum that makes updating them actually roll the pods.
#
# Updating a ConfigMap does not restart anything. Kubernetes re-projects
# directory mounts after about a minute, subPath mounts never update at all,
# and no rollout is triggered either way. Only a change to the pod template
# creates a new ReplicaSet, so the checksum goes into the template's
# annotations: change the databases, the checksum changes, the pods roll, and
# the new couriertcpd opens the new files.
#
# That last part is the point. couriertcpd holds smtpaccess.dat open for the
# life of the process -- measured on farout as fd 4 -- so replacing the file
# underneath it changes nothing. Restarting the pod is the only way the new
# rules take effect, which makes "update the config" and "roll the pods" the
# same operation rather than two things an operator has to remember to pair.
#
# Split by sensitivity: the four config databases are a ConfigMap, userdb.dat
# and userdbshadow.dat are a Secret, because the shadow file is password
# hashes.

set -u -o pipefail

DAT_COURIER="${DAT_COURIER:-}"
DAT_AUTHLIB="${DAT_AUTHLIB:-}"
NAMESPACE="${NAMESPACE:-mailbag}"
OUT="${OUT:-}"

usage() {
    cat >&2 <<EOF
usage: $0 --courier DIR --authlib DIR [--namespace NS] [--out FILE]
  --courier DIR    directory holding the four config .dat files
  --authlib DIR    directory holding userdb.dat and userdbshadow.dat
  --out FILE       write the manifests here (default: stdout)
Prints the content checksum to stderr so a caller can stamp it on pod templates.
EOF
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --courier)   DAT_COURIER=${2:?}; shift 2 ;;
        --authlib)   DAT_AUTHLIB=${2:?}; shift 2 ;;
        --namespace) NAMESPACE=${2:?}; shift 2 ;;
        --out)       OUT=${2:?}; shift 2 ;;
        -h|--help)   usage ;;
        *) echo "$0: unknown argument '$1'" >&2; usage ;;
    esac
done

die() { echo "package-courier-dat: FATAL: $*" >&2; exit 1; }

[ -n "$DAT_COURIER" ] && [ -n "$DAT_AUTHLIB" ] || usage
[ -d "$DAT_COURIER" ] || die "not a directory: $DAT_COURIER"
[ -d "$DAT_AUTHLIB" ] || die "not a directory: $DAT_AUTHLIB"

CONFIG_DAT=(hosteddomains.dat esmtpacceptmailfor.dat smtpaccess.dat aliases.dat)
SECRET_DAT=(userdb.dat userdbshadow.dat)

for f in "${CONFIG_DAT[@]}"; do
    [ -s "$DAT_COURIER/$f" ] || die "missing or empty: $DAT_COURIER/$f"
done
for f in "${SECRET_DAT[@]}"; do
    [ -s "$DAT_AUTHLIB/$f" ] || die "missing or empty: $DAT_AUTHLIB/$f"
done

# One checksum over every packaged file, in a fixed order so it is stable.
#
# `sha256sum < file` rather than `sha256sum file`: reading stdin keeps the
# filename out of the output, so the value depends on content alone and a build
# in a different directory still produces the same checksum. The file lists are
# fixed arrays rather than globs so the concatenation order cannot vary with
# locale or directory read order. Truncated to 16 hex characters because this
# is a "did it change" marker, not a security boundary.
#
# Logged per-file to stderr. This value is generated outside the deployment and
# then decides whether pods roll, so the moment it is produced should be
# visible in the job output rather than inferred later from a rollout.
echo "==> checksumming packaged databases" >&2
per_file=$(
    {
        for f in "${CONFIG_DAT[@]}"; do
            h=$(sha256sum < "$DAT_COURIER/$f") || exit 1
            printf '%s  configmap/%s\n' "$h" "$f"
        done
        for f in "${SECRET_DAT[@]}"; do
            h=$(sha256sum < "$DAT_AUTHLIB/$f") || exit 1
            printf '%s  secret/%s\n' "$h" "$f"
        done
    }
) || die "checksum failed"

while IFS= read -r line; do
    printf '    %s  %s\n' "${line%% *}" "${line##*  }" >&2
done <<< "$per_file"

CHECKSUM=$(printf '%s\n' "$per_file" | awk '{print $1}' | sha256sum | cut -c1-16) \
    || die "checksum failed"
echo "    => dat-checksum $CHECKSUM (pods roll when this changes)" >&2

emit() {
    echo "apiVersion: v1"
    echo "kind: ConfigMap"
    echo "metadata:"
    echo "  name: courier-dat"
    echo "  namespace: $NAMESPACE"
    echo "  labels:"
    echo "    app: mailbag"
    echo "  annotations:"
    echo "    mailbag.rton.me/dat-checksum: \"$CHECKSUM\""
    echo "# GDBM databases are binary, so they go in binaryData rather than data."
    echo "binaryData:"
    for f in "${CONFIG_DAT[@]}"; do
        echo "  $f: $(base64 -w0 < "$DAT_COURIER/$f")"
    done
    echo "---"
    echo "apiVersion: v1"
    echo "kind: Secret"
    echo "metadata:"
    echo "  name: courier-userdb"
    echo "  namespace: $NAMESPACE"
    echo "  labels:"
    echo "    app: mailbag"
    echo "  annotations:"
    echo "    mailbag.rton.me/dat-checksum: \"$CHECKSUM\""
    echo "# userdbshadow.dat is password hashes, so this is a Secret, not a ConfigMap."
    echo "type: Opaque"
    echo "data:"
    for f in "${SECRET_DAT[@]}"; do
        echo "  $f: $(base64 -w0 < "$DAT_AUTHLIB/$f")"
    done
}

if [ -n "$OUT" ]; then emit > "$OUT" || die "write failed: $OUT"; else emit; fi
echo "$CHECKSUM"
