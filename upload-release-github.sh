#!/bin/bash
# Push commits/tags and, for a full release, create/update the GitHub release.
#
# Usage: ./upload-release-github.sh [TAG] [NEWVER] [FULL]
#   TAG     tag to push (may be empty for a plain pre-release with no new tag)
#   NEWVER  X.Y.Z version for the GitHub release (required when FULL=true)
#   FULL    "true" to create/update a GitHub release from the X.Y.Z tag
#
# Normally invoked by release.sh, but can be run standalone to (re)push and
# (re)publish a release; the GitHub release step is idempotent.
case "${1:-}" in
    -h|--help)
        echo "Usage: ./upload-release-github.sh [TAG] [NEWVER] [FULL]" >&2
        echo "" >&2
        echo "  TAG     tag to push (may be empty for a pre-release with no new tag)" >&2
        echo "  NEWVER  X.Y.Z version for the GitHub release (required when FULL=true)" >&2
        echo "  FULL    \"true\" to create/update a GitHub release from the X.Y.Z tag" >&2
        echo "" >&2
        echo "Pushes commits/tags and, when FULL, creates or updates the GitHub" >&2
        echo "release (idempotent). Normally invoked by release.sh." >&2
        exit 0 ;;
esac
set -e
CI_PROJECT_DIR=$(git rev-parse --show-toplevel)
cd "$CI_PROJECT_DIR"

TAG="${1:-}"
NEWVER="${2:-}"
FULL="${3:-false}"

git push
if [[ -n "$TAG" ]]; then
    git push origin "$TAG"
fi

# Full (non-pre) release: create the GitHub release from the X.Y.Z tag.
# This covers both a bumped full release and a promoted pre-release.
# Idempotent and non-interactive: if the release already exists (e.g. a
# previous run failed mid-way), just (re)upload the assets; otherwise create
# it. Assets are attached by full path (gh resolves bare filenames relative
# to the cwd, not release/).
if [[ "$FULL" == "true" ]]; then
    if [[ -z "$NEWVER" ]]; then
        echo "ERROR: full release requested but no version given." >&2
        exit 1
    fi
    if gh release view "${NEWVER}" >/dev/null 2>&1; then
        echo "GitHub release ${NEWVER} already exists; uploading assets."
        gh release upload "${NEWVER}" \
            "$CI_PROJECT_DIR"/release/Propulse-*.zip --clobber
    else
        # Title is just the version; notes are left empty on purpose so commit
        # messages never leak into the release text (use --notes "" rather than
        # --generate-notes). Edit the notes on GitHub afterwards if desired.
        gh release create "${NEWVER}" \
            "$CI_PROJECT_DIR"/release/Propulse-*.zip \
            --title "${NEWVER}" \
            --notes "" \
            --verify-tag \
            --latest
    fi
fi
