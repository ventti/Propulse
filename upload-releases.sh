#!/bin/bash
set -exuo pipefail

CI_PROJECT_DIR=${CI_PROJECT_DIR:-$(git rev-parse --show-toplevel)}
PROJECT_NAME="Propulse-EXT"
DROPBOX_UPLOADER="${CI_PROJECT_DIR}/tools/scripts/dropbox_uploader.sh"

dropbox_upload() {
    "${DROPBOX_UPLOADER}" -f "${CI_PROJECT_DIR}/.dropboxuploader" upload "${1}" "${2}"
}
dropbox_mkdir() {
    "${DROPBOX_UPLOADER}" -f "${CI_PROJECT_DIR}/.dropboxuploader" mkdir "${1}"
}


for file in "$CI_PROJECT_DIR"/release/Propulse-*.zip; do
    filename=$(basename "${file}")
    zip_root=$(zipinfo -1 "${file}" 2>/dev/null | head -1 | cut -d/ -f1 || true)
    [ -z "${zip_root}" ] && { echo "Error: invalid zip ${file}" >&2; exit 1; }
    VERSION=$(unzip -p "${file}" "${zip_root}/version.txt" 2>/dev/null | tr -d '\r\n' || true)

    if [ -z "${VERSION}" ]; then
        echo "Error: version.txt not found in ${file}" >&2
        exit 1
    fi
    {
        dropbox_mkdir "${PROJECT_NAME}/releases" || true
        dropbox_mkdir "${PROJECT_NAME}/releases/latest" || true
        dropbox_mkdir "${PROJECT_NAME}/releases/${VERSION}" || true
    } >/dev/null 2>&1

    dropbox_upload "${file}" "${PROJECT_NAME}/releases/${VERSION}/${filename}"
    dropbox_upload "${file}" "${PROJECT_NAME}/releases/latest/${filename}"
done

dropbox_upload "${CI_PROJECT_DIR}/CHANGELOG.txt" "${PROJECT_NAME}/releases/latest/CHANGELOG.txt"
