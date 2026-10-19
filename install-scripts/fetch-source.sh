# Sourced by the install-*.sh scripts.
#
#   fetch_source <sourceforge dir> <tarball> <sha256>
#
# Downloads a Courier source tarball from SourceForge and verifies it against
# the sha256 pinned in cue/packages.cue (passed in as a build arg) before
# anything is extracted. curl -f, because without it a mirror's error page is
# saved as the tarball and the build fails later, at tar, for no visible
# reason. If SOURCE_DIR holds the tarball, that copy is used instead of the
# network -- the goss check of a mismatched checksum runs that way, offline.

fetch_source() {
    local dir=$1 file=$2 sha256=$3
    if [ -z "$sha256" ]; then
        echo "fetch_source: no sha256 for $file" >&2
        return 1
    fi
    if [ -n "${SOURCE_DIR:-}" ] && [ -f "$SOURCE_DIR/$file" ]; then
        cp "$SOURCE_DIR/$file" "$file"
    else
        curl -fsSL --retry 3 -o "$file" \
            "https://sourceforge.net/projects/courier/files/$dir/$file/download"
    fi
    if ! echo "$sha256  $file" | sha256sum -c --quiet -; then
        echo "fetch_source: sha256 mismatch for $file" >&2
        return 1
    fi
}
