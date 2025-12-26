#!/bin/bash
set -exuo pipefail

CI_PROJECT_DIR=${CI_PROJECT_DIR:-$(git rev-parse --show-toplevel)}
PROJECT_NAME="Propulse-EXT"
UPLOADER="${CI_PROJECT_DIR}/tools/scripts/dropbox_uploader.sh"
UPLOADER_OPTS=(-f "${CI_PROJECT_DIR}/.dropboxuploader")

for file in "$CI_PROJECT_DIR"/release/Propulse-*.zip; do
    filename=$(basename "${file}")
    zip_root=$(zipinfo -1 "${file}" 2>/dev/null | head -1 | cut -d/ -f1 || true)
    [ -z "${zip_root}" ] && { echo "Error: invalid zip ${file}" >&2; exit 1; }
    VERSION=$(unzip -p "${file}" "${zip_root}/version.txt" 2>/dev/null | tr -d '\r\n' || true)
    
    if [ -z "${VERSION}" ]; then
        echo "Error: version.txt not found in ${file}" >&2
        exit 1
    fi

    "${UPLOADER}" "${UPLOADER_OPTS[@]}" mkdir "${PROJECT_NAME}/releases" &>/dev/null || true
    "${UPLOADER}" "${UPLOADER_OPTS[@]}" mkdir "${PROJECT_NAME}/releases/latest" &>/dev/null || true
    "${UPLOADER}" "${UPLOADER_OPTS[@]}" mkdir "${PROJECT_NAME}/releases/${VERSION}" &>/dev/null || true
    "${UPLOADER}" "${UPLOADER_OPTS[@]}" upload "${file}" "${PROJECT_NAME}/releases/${VERSION}/${filename}"
    "${UPLOADER}" "${UPLOADER_OPTS[@]}" upload "${file}" "${PROJECT_NAME}/releases/latest/${filename}"
done
