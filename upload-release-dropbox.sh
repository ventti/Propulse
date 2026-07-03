#!/bin/bash

usage() {
    echo "Usage: ./upload-release-dropbox.sh [--ignore-missing] [--verbose]" >&2
    echo "" >&2
    echo "Upload the built release/ artifacts to Dropbox. Requires a configured" >&2
    echo ".dropboxuploader in the project root." >&2
    echo "" >&2
    echo "  --ignore-missing  skip any missing artifact instead of failing" >&2
    echo "  --verbose         trace every command (the old default output)" >&2
    echo "  -h, --help        show this help" >&2
}

IGNORE_MISSING=false
VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        --ignore-missing) IGNORE_MISSING=true ;;
        --verbose)        VERBOSE=true ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; usage; exit 1 ;;
    esac
done

set -euo pipefail
$VERBOSE && set -x

CI_PROJECT_DIR=${CI_PROJECT_DIR:-$(git rev-parse --show-toplevel)}
PROJECT_NAME="Propulse-EXT"
DROPBOX_UPLOADER="${CI_PROJECT_DIR}/tools/scripts/dropbox_uploader.sh"

DROPBOX_CONFIG="${CI_PROJECT_DIR}/.dropboxuploader"

# Without a valid config, dropbox_uploader.sh drops into an interactive OAuth
# setup and blocks on stdin (and the mkdir block below hides it, so it looks
# like a silent hang). Fail fast with a clear message instead.
if [[ ! -s "${DROPBOX_CONFIG}" ]]; then
    echo "ERROR: Dropbox config not found or empty: ${DROPBOX_CONFIG}" >&2
    echo "Provide a configured .dropboxuploader before running this script." >&2
    exit 1
fi

# In the default (strict) mode, validate all required build artifacts up front
# so we never do a partial upload (previously a missing CHANGELOG.txt failed
# only after the zips had already been pushed). With --ignore-missing we skip
# this and simply upload whatever exists. Artifacts are produced by
# build-all-releases.sh and generate-changelog.sh; run release.sh for the
# whole pipeline in order.
if ! $IGNORE_MISSING; then
    if ! ls "${CI_PROJECT_DIR}"/release/Propulse-*.zip >/dev/null 2>&1; then
        echo "ERROR: no release/Propulse-*.zip found. Run build-all-releases.sh first." >&2
        exit 1
    fi
    for req in version.txt CHANGELOG.txt; do
        if [[ ! -f "${CI_PROJECT_DIR}/release/${req}" ]]; then
            echo "ERROR: missing release/${req}. Run build-all-releases.sh and generate-changelog.sh first (or use release.sh)." >&2
            exit 1
        fi
    done
fi

# Redirect stdin from /dev/null so the uploader can never block waiting for
# interactive input; it will error out instead of hanging.
dropbox_upload() {
    "${DROPBOX_UPLOADER}" -f "${DROPBOX_CONFIG}" upload "${1}" "${2}" </dev/null
}
dropbox_mkdir() {
    "${DROPBOX_UPLOADER}" -f "${DROPBOX_CONFIG}" mkdir "${1}" </dev/null
}

# Upload one file if it exists; otherwise skip (--ignore-missing) or fail.
maybe_upload() {
    if [[ -f "${1}" ]]; then
        dropbox_upload "${1}" "${2}"
    elif $IGNORE_MISSING; then
        echo "Skipping missing file: ${1}" >&2
    else
        echo "ERROR: missing file: ${1}" >&2
        exit 1
    fi
}

VERSION=""
if [[ -f "${CI_PROJECT_DIR}/release/version.txt" ]]; then
    VERSION=$(cat "${CI_PROJECT_DIR}/release/version.txt")
fi

{
    dropbox_mkdir "${PROJECT_NAME}/releases" || true
    dropbox_mkdir "${PROJECT_NAME}/releases/latest" || true
    if [[ -n "${VERSION}" ]]; then
        dropbox_mkdir "${PROJECT_NAME}/releases/${VERSION}" || true
    fi
} >/dev/null 2>&1


for file in "$CI_PROJECT_DIR"/release/Propulse-*.zip; do
    # No matches leaves the glob literal, which isn't a file; skip it.
    [[ -f "${file}" ]] || continue
    filename=$(basename "${file}")
    if [[ -n "${VERSION}" ]]; then
        dropbox_upload "${file}" "${PROJECT_NAME}/releases/${VERSION}/${filename}"
    fi
    dropbox_upload "${file}" "${PROJECT_NAME}/releases/latest/${filename}"
done

maybe_upload "${CI_PROJECT_DIR}/release/version.txt"   "${PROJECT_NAME}/releases/latest/version.txt"
maybe_upload "${CI_PROJECT_DIR}/release/CHANGELOG.txt" "${PROJECT_NAME}/releases/latest/CHANGELOG.txt"
