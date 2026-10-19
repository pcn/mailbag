#!/bin/bash
# Print the userdb source for a context: one record per declared mailbox, from
# userdb.template, each with its systempw from the passwords file.
#
#   userdb-source.sh RENDERER TEMPLATE CONTEXT PASSWORDS > userdb/mailboxes
#
# The database build job runs this (build-courier-dat.sh); goss/repo.yaml
# runs it against fixtures. PASSWORDS holds address:hash lines (comments and
# blank lines allowed). Exits non-zero, printing which addresses and never a
# hash, when the two disagree: a declared mailbox with no hash, a hash for an
# address that is not a mailbox, or an address with two hashes. Guessing
# would either lock someone out or keep a removed login alive.
#
# PROJ-040.

set -u -o pipefail

renderer="${1:?usage: $0 RENDERER TEMPLATE CONTEXT PASSWORDS}"
template="${2:?usage: $0 RENDERER TEMPLATE CONTEXT PASSWORDS}"
context="${3:?usage: $0 RENDERER TEMPLATE CONTEXT PASSWORDS}"
passwords="${4:?usage: $0 RENDERER TEMPLATE CONTEXT PASSWORDS}"

[ -r "$passwords" ] || { echo "userdb-source: passwords file not readable: $passwords" >&2; exit 1; }
records=$("$renderer" --strict -n "$template" "$context") \
    || { echo "userdb-source: rendering $template failed" >&2; exit 1; }

# Append "|systempw=<hash>" to each record.
awk -F'\t' '
    FNR == NR {
        if ($0 ~ /^[[:space:]]*(#|$)/) next
        i = index($0, ":")
        if (i < 2) { printf "userdb-source: malformed passwords line %d\n", FNR > "/dev/stderr"; bad = 1; next }
        a = substr($0, 1, i - 1)
        if (a in hash) { printf "userdb-source: %s has more than one hash\n", a > "/dev/stderr"; bad = 1 }
        hash[a] = substr($0, i + 1)
        next
    }
    /^[[:space:]]*(#|$)/ { next }
    {
        if (!($1 in hash)) { printf "userdb-source: mailbox %s has no password hash\n", $1 > "/dev/stderr"; bad = 1; next }
        print $0 "|systempw=" hash[$1]
        used[$1] = 1
    }
    END {
        for (a in hash) if (!(a in used)) { printf "userdb-source: a hash names %s, which is not a declared mailbox\n", a > "/dev/stderr"; bad = 1 }
        exit bad
    }' "$passwords" <(printf '%s\n' "$records")
