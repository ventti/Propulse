#!/bin/bash
set -e
CI_PROJECT_DIR=$(git rev-parse --show-toplevel)
cd "$CI_PROJECT_DIR"

usage() {
    echo "Usage: ./release.sh [--pre] [major|minor|patch]" >&2
    echo "" >&2
    echo "  (no args)                 pre-release, no new tag" >&2
    echo "  --pre                      pre-release, no new tag" >&2
    echo "  --pre major|minor|patch    bump version, tag X.Y.Z-pre, no GitHub release" >&2
    echo "  major|minor|patch          bump version, tag X.Y.Z, create GitHub release" >&2
    exit 1
}

PRE=false
BUMP=""
for arg in "$@"; do
    case "$arg" in
        --pre)               PRE=true ;;
        major|minor|patch)   BUMP="$arg" ;;
        -h|--help)           usage ;;
        *) echo "Unknown argument: $arg" >&2; usage ;;
    esac
done

# No dirty releases or pre-releases.
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree is not clean. Commit or stash changes first." >&2
    exit 1
fi

TAG=""
NEWVER=""
if [[ -n "$BUMP" ]]; then
    # Bump from the highest existing X.Y.Z tag (ignore -pre and other tags).
    LATEST=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    LATEST=${LATEST:-0.0.0}
    IFS=. read -r MA MI PA <<< "$LATEST"
    case "$BUMP" in
        major) MA=$((MA + 1)); MI=0; PA=0 ;;
        minor) MI=$((MI + 1)); PA=0 ;;
        patch) PA=$((PA + 1)) ;;
    esac
    NEWVER="${MA}.${MI}.${PA}"

    if $PRE; then
        TAG="${NEWVER}-pre"
    else
        TAG="${NEWVER}"
    fi

    if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
        echo "Tag ${TAG} already exists; not recreating."
    else
        # Tag before building so the version is baked into the binaries.
        git tag "${TAG}"
        echo "Created tag ${TAG}"
    fi
fi

./build-all-releases.sh
./generate-changelog.sh
./upload-releases.sh

git push
if [[ -n "$TAG" ]]; then
    git push origin "$TAG"
fi

# Full (non-pre) release: create the GitHub release from the X.Y.Z tag.
if ! $PRE && [[ -n "$BUMP" ]]; then
    gh release create "${NEWVER}"
    for file in "$CI_PROJECT_DIR"/release/Propulse-*.zip; do
        filename=$(basename "${file}")
        gh release upload "${NEWVER}" "${filename}"
    done
fi
