#!/bin/bash
case "${1:-}" in
    -h|--help)
        echo "Usage: ./upload-release-dropbox.sh" >&2
        echo "" >&2
        echo "Upload the built release/ artifacts to Dropbox. Requires a configured" >&2
        echo ".dropboxuploader in the project root. Takes no arguments." >&2
        exit 0 ;;
esac
set -exuo pipefail

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

# Validate all required build artifacts up front so we never do a partial
# upload (previously a missing CHANGELOG.txt failed only after the zips had
# already been pushed). These are produced by build-all-releases.sh and
# generate-changelog.sh; run release.sh to do the whole pipeline in order.
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

# Redirect stdin from /dev/null so the uploader can never block waiting for
# interactive input; it will error out instead of hanging.
dropbox_upload() {
    "${DROPBOX_UPLOADER}" -f "${DROPBOX_CONFIG}" upload "${1}" "${2}" </dev/null
}
dropbox_mkdir() {
    "${DROPBOX_UPLOADER}" -f "${DROPBOX_CONFIG}" mkdir "${1}" </dev/null
}

VERSION=$(cat "${CI_PROJECT_DIR}/release/version.txt")
{
    dropbox_mkdir "${PROJECT_NAME}/releases" || true
    dropbox_mkdir "${PROJECT_NAME}/releases/latest" || true
    dropbox_mkdir "${PROJECT_NAME}/releases/${VERSION}" || true
} >/dev/null 2>&1


for file in "$CI_PROJECT_DIR"/release/Propulse-*.zip; do
    filename=$(basename "${file}")
    dropbox_upload "${file}" "${PROJECT_NAME}/releases/${VERSION}/${filename}"
    dropbox_upload "${file}" "${PROJECT_NAME}/releases/latest/${filename}"
done

dropbox_upload "${CI_PROJECT_DIR}/release/version.txt" "${PROJECT_NAME}/releases/latest/version.txt"
dropbox_upload "${CI_PROJECT_DIR}/release/CHANGELOG.txt" "${PROJECT_NAME}/releases/latest/CHANGELOG.txt"
