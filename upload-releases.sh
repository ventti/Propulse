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

VERSION=$(cat "${CI_PROJECT_DIR}/release/version.txt")
{
    dropbox_mkdir "${PROJECT_NAME}/releases" || true
    dropbox_mkdir "${PROJECT_NAME}/releases/latest" || true
    dropbox_mkdir "${PROJECT_NAME}/releases/${VERSION}" || true
} >/dev/null 2>&1

dropbox_upload "${CI_PROJECT_DIR}/release/CHANGELOG.txt" "${PROJECT_NAME}/releases/latest/CHANGELOG.txt"
dropbox_upload "${CI_PROJECT_DIR}/release/version.txt" "${PROJECT_NAME}/releases/latest/version.txt"

for file in "$CI_PROJECT_DIR"/release/Propulse-*.zip; do
    filename=$(basename "${file}")
    dropbox_upload "${file}" "${PROJECT_NAME}/releases/${VERSION}/${filename}"
    dropbox_upload "${file}" "${PROJECT_NAME}/releases/latest/${filename}"
done

