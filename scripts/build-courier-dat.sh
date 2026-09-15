#!/bin/bash
#
# Build and validate every courier-derived .dat file, out of band.
#
# Serving pods used to do this at startup: five containers each running
# makeuserdb, makehosteddomains, makeacceptmailfor, makesmtpaccess and
# makealiases against shared volumes. That is five chances to fail, in the
# place where failure costs inbound mail, and the result depended on which pod
# ran last -- aliases.dat on farout was keyed to a pod name because mta-ssl
# happened to win the race.
#
# This builds everything once, proves it is usable, and only then publishes it.
# A bad build fails this script; the live databases are never touched.
#
# Two details drive the structure:
#
#   - The make* wrappers are thin shells that hardcode sysconfdir and then call
#     makedat with explicit -src/-file/-tmp. We call the underlying tools
#     directly: the wrappers would write to the live tree, and makesmtpaccess
#     additionally runs `couriertcpd -restart`, which has no business in a
#     build job.
#
#   - makeuserdb derives each record's "_=" location field from the
#     compiled-in @userdb@ prefix (makeuserdb.in:132), not from -f. So the
#     userdb source has to be built at its canonical path or the location
#     fields come out wrong. We therefore build at the canonical paths inside
#     this container -- which are ephemeral here -- and publish to the live
#     volumes afterwards.

set -u -o pipefail

CONTEXT="${CONTEXT:-/context.json}"
TEMPLATES="${TEMPLATES:-/templates}"
RENDER="${RENDER:-/render-template}"
VALIDATE="${VALIDATE:-/usr/local/bin/validate-courier-dat.pl}"
PUBLISH_COURIER="${PUBLISH_COURIER:-}"
PUBLISH_AUTHLIB="${PUBLISH_AUTHLIB:-}"
USERDB_SRC="${USERDB_SRC:-}"
CANARY="${CANARY:-}"

COURIER=/etc/courier
AUTHLIB=/etc/authlib
BINDIR=/usr/lib/courier/bin
SBINDIR=/usr/lib/courier/sbin

usage() {
    cat >&2 <<EOF
usage: $0 [options]
  --context FILE           context.json (default: $CONTEXT)
  --templates DIR          rendered-template source dir (default: $TEMPLATES)
  --publish-courier DIR    live /etc/courier volume to publish into
  --publish-authlib DIR    live /etc/authlib volume to publish into
  --userdb-src DIR         copy the userdb source from here before building
  --canary ADDRESS         userdb address that must resolve after the build
Without --publish-*, builds and validates only. That is the dry run.
EOF
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --context)         CONTEXT=${2:?}; shift 2 ;;
        --templates)       TEMPLATES=${2:?}; shift 2 ;;
        --publish-courier) PUBLISH_COURIER=${2:?}; shift 2 ;;
        --publish-authlib) PUBLISH_AUTHLIB=${2:?}; shift 2 ;;
        --userdb-src)      USERDB_SRC=${2:?}; shift 2 ;;
        --canary)          CANARY=${2:?}; shift 2 ;;
        -h|--help)         usage ;;
        *) echo "$0: unknown argument '$1'" >&2; usage ;;
    esac
done

die()  { echo "build-courier-dat: FATAL: $*" >&2; exit 1; }
step() { echo "==> $*"; }

[ -r "$CONTEXT" ]   || die "context not readable: $CONTEXT"
[ -d "$TEMPLATES" ] || die "templates dir not found: $TEMPLATES"
[ -x "$RENDER" ]    || die "renderer not found: $RENDER"
[ -x "$VALIDATE" ]  || die "validator not found: $VALIDATE"

render() {
    local tmpl="$TEMPLATES/$1" out="$2"
    [ -r "$tmpl" ] || die "template not found: $tmpl"
    "$RENDER" --context "$CONTEXT" --template "$tmpl" > "$out" \
        || die "rendering $1 failed"
}

# Count source records the way the .dat should: skip comments and blanks.
count_src() {
    local path="$1"
    if [ -d "$path" ]; then cat "$path"/* 2>/dev/null; else cat "$path" 2>/dev/null; fi \
        | grep -cvE '^[[:space:]]*(#|$)' || true
}

# ------------------------------------------------------------------ sources
# The userdb source usually lives on a volume, but makeuserdb has to run with it
# at the compiled-in path: it derives each record's "_=" location field from the
# @userdb@ prefix (makeuserdb.in:132), not from -f, so building against a volume
# path writes wrong location fields. Copy it to the canonical path, which in a
# build job is ephemeral, and publish the results back afterwards. That is also
# what keeps a failed build from touching the live databases.
if [ -n "$USERDB_SRC" ]; then
    [ -d "$USERDB_SRC" ] || die "userdb source not a directory: $USERDB_SRC"
    step "copying userdb source from $USERDB_SRC"
    mkdir -p "$AUTHLIB/userdb" || die "mkdir $AUTHLIB/userdb failed"
    # The source directory carries lock files and courier's own scratch entries;
    # only the per-domain files are input.
    copied=0
    for f in "$USERDB_SRC"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            .*|dummy) continue ;;
        esac
        cp -p "$f" "$AUTHLIB/userdb/" || die "copying $f failed"
        copied=$((copied + 1))
    done
    [ "$copied" -gt 0 ] || die "no userdb source files found in $USERDB_SRC"
    chmod 700 "$AUTHLIB/userdb"
    echo "    copied $copied source file(s)"
fi

step "rendering sources from $CONTEXT"
mkdir -p "$COURIER/esmtpacceptmailfor.dir" "$COURIER/smtpaccess" \
         "$COURIER/aliases" "$COURIER/aliasdir" "$AUTHLIB/userdb" || die "mkdir failed"

render hosteddomains.template      "$COURIER/hosteddomains"
render acceptmailfor.template      "$COURIER/esmtpacceptmailfor.dir/context"
render smtpaccess-default.template "$COURIER/smtpaccess/default"
render aliases.template            "$COURIER/aliases/mailbag"

# courier ships aliases/system with bare local parts that makealiases qualifies
# with the local hostname. In a container that is the pod name, so it has to go
# -- aliases.template emits fully qualified entries instead.
rm -f "$COURIER/aliases/system"

# ------------------------------------------------------------------- build
step "building config databases"
"$BINDIR/makedat" -src="$COURIER/hosteddomains" \
    -file="$COURIER/hosteddomains.dat" -tmp="$COURIER/hosteddomains.tmp" \
    || die "makedat hosteddomains failed"
"$BINDIR/makedat" -src="$COURIER/esmtpacceptmailfor.dir" \
    -file="$COURIER/esmtpacceptmailfor.dat" -tmp="$COURIER/esmtpacceptmailfor.tmp" \
    || die "makedat esmtpacceptmailfor failed"
# -cidr matches what makesmtpaccess passes: these keys are address ranges.
"$BINDIR/makedat" -src="$COURIER/smtpaccess" \
    -file="$COURIER/smtpaccess.dat" -tmp="$COURIER/smtpaccess.tmp" -cidr \
    || die "makedat smtpaccess failed"

step "building aliases"
"$SBINDIR/makealiases" || die "makealiases failed"

step "building userdb"
[ -n "$(ls -A "$AUTHLIB/userdb" 2>/dev/null)" ] \
    || die "$AUTHLIB/userdb is empty: refusing to publish an empty user database"

# Check the source before building it. makeuserdb does not reject a line it
# cannot parse -- makeuserdb.in prints any line without a tab straight through
# to makedat, which then makes a record out of the garbage. The record count
# still matches the source line count, so no downstream assertion catches it:
# a typo'd source produces a database that validates and does not work.
#
# A record is ADDRESS<TAB>field|field. Anything else is a mistake.
bad=0
while IFS= read -r line; do
    printf '%s\n' "$line" | grep -qE '^[[:space:]]*(#|$)' && continue
    case "$line" in
        *"$(printf '\t')"*) ;;
        *) echo "    malformed (no tab): $line" >&2; bad=1; continue ;;
    esac
    addr=${line%%"$(printf '\t')"*}
    rest=${line#*"$(printf '\t')"}
    [ -n "$addr" ] || { echo "    malformed (no address): $line" >&2; bad=1; }
    [ -n "$rest" ] || { echo "    malformed (no fields): $line" >&2; bad=1; }
done < <(cat "$AUTHLIB/userdb"/* 2>/dev/null)
[ "$bad" -eq 0 ] || die "userdb source is malformed; refusing to build"

/usr/sbin/makeuserdb || die "makeuserdb failed"

# ---------------------------------------------------------------- validate
step "validating"
rc=0
v() { "$VALIDATE" "$@" || rc=1; }

v --dat "$COURIER/hosteddomains.dat" --label hosteddomains.dat \
  --expect-records "$(count_src "$COURIER/hosteddomains")"
v --dat "$COURIER/esmtpacceptmailfor.dat" --label esmtpacceptmailfor.dat \
  --expect-records "$(count_src "$COURIER/esmtpacceptmailfor.dir")"
v --dat "$COURIER/smtpaccess.dat" --label smtpaccess.dat \
  --expect-records "$(count_src "$COURIER/smtpaccess")"

# aliases maps 1:1 only when entries are fully qualified, which ours are. In
# "reject" mode the source is comments alone and zero records is the intent,
# so this is the one file that takes a floor rather than an exact count.
v --dat "$COURIER/aliases.dat" --label aliases.dat \
  --min-records "$(count_src "$COURIER/aliases")"

# The two userdb databases are written through independent pipes, so each is
# checked separately: one can be fine while the other is not.
userdb_expected=$(count_src "$AUTHLIB/userdb")
if [ -n "$CANARY" ]; then
    v --dat "$AUTHLIB/userdb.dat" --label userdb.dat \
      --expect-records "$userdb_expected" --canary "$CANARY" --canary-match 'uid='
    v --dat "$AUTHLIB/userdbshadow.dat" --label userdbshadow.dat \
      --expect-records "$userdb_expected" --canary "$CANARY" --canary-match 'pw='
else
    echo "    (no --canary given; record counts only for userdb)" >&2
    v --dat "$AUTHLIB/userdb.dat" --label userdb.dat --expect-records "$userdb_expected"
    v --dat "$AUTHLIB/userdbshadow.dat" --label userdbshadow.dat --expect-records "$userdb_expected"
fi

# The two halves have to agree. Accepting mail is gated twice and
# independently: couriertcpd refuses a domain that is not in acceptmailfor
# (513 Relaying denied), and courierlocal refuses an address with no userdb
# entry (550 User unknown). So an account whose domain was never added to
# accept_mail_for is silently unreachable, and an accepted domain with no
# accounts refuses everything -- in both cases the configuration looks fine and
# the mail does not arrive.
step "cross-checking userdb domains against hosted domains"
hosted=$(grep -vE '^[[:space:]]*(#|$)' "$COURIER/hosteddomains" | awk '{print $1}' | sort -u)
userdb_domains=$(cat "$AUTHLIB/userdb"/* 2>/dev/null \
    | grep -vE '^[[:space:]]*(#|$)' \
    | awk -F'\t' '{print $1}' | awk -F@ 'NF>1 {print $NF}' | sort -u)

for d in $userdb_domains; do
    if ! printf '%s\n' "$hosted" | grep -qxF "$d"; then
        echo "    accounts exist for '$d' but it is not a hosted domain" >&2
        rc=1
    fi
done
for d in $hosted; do
    if ! printf '%s\n' "$userdb_domains" | grep -qxF "$d"; then
        # Not fatal: a domain may be accepted and relayed onward rather than
        # delivered locally, and aliases can resolve to another domain.
        echo "    note: hosted domain '$d' has no local accounts" >&2
    fi
done
[ "$rc" -eq 0 ] || die "userdb and hosteddomains disagree; refusing to publish"
echo "    $(printf '%s\n' "$userdb_domains" | grep -c .) domain(s) with accounts, all hosted"

[ "$rc" -eq 0 ] || die "validation failed; nothing published, live databases untouched"

# ----------------------------------------------------------------- publish
publish() {
    local src="$1" dst_dir="$2" name
    name=$(basename "$src")
    # Copy then rename: courier relies on the OS doing the atomic switch and
    # does not cache, so a reader sees either the old file or the new one.
    cp -p "$src" "$dst_dir/.$name.new" || die "copy $name failed"
    mv -f "$dst_dir/.$name.new" "$dst_dir/$name" || die "publish $name failed"
    echo "    published $dst_dir/$name"
}

if [ -n "$PUBLISH_COURIER" ]; then
    [ -d "$PUBLISH_COURIER" ] || die "publish target not a directory: $PUBLISH_COURIER"
    step "publishing config to $PUBLISH_COURIER"
    mkdir -p "$PUBLISH_COURIER/esmtpacceptmailfor.dir" "$PUBLISH_COURIER/smtpaccess" \
             "$PUBLISH_COURIER/aliases"
    for f in hosteddomains hosteddomains.dat esmtpacceptmailfor.dat \
             smtpaccess.dat aliases.dat; do
        publish "$COURIER/$f" "$PUBLISH_COURIER"
    done
    publish "$COURIER/esmtpacceptmailfor.dir/context" "$PUBLISH_COURIER/esmtpacceptmailfor.dir"
    publish "$COURIER/smtpaccess/default"             "$PUBLISH_COURIER/smtpaccess"
    publish "$COURIER/aliases/mailbag"                "$PUBLISH_COURIER/aliases"
    rm -f "$PUBLISH_COURIER/aliases/system"
fi

if [ -n "$PUBLISH_AUTHLIB" ]; then
    [ -d "$PUBLISH_AUTHLIB" ] || die "publish target not a directory: $PUBLISH_AUTHLIB"
    step "publishing userdb to $PUBLISH_AUTHLIB"
    for f in userdb.dat userdbshadow.dat; do
        publish "$AUTHLIB/$f" "$PUBLISH_AUTHLIB"
    done
fi

if [ -z "$PUBLISH_COURIER" ] && [ -z "$PUBLISH_AUTHLIB" ]; then
    step "dry run: built and validated, nothing published"
fi
echo "build-courier-dat: ok"
