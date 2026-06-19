#!/bin/bash
set -e
CI_PROJECT_DIR=$(git rev-parse --show-toplevel)
cd "$CI_PROJECT_DIR"

usage() {
    echo "Usage: ./release.sh [--pre | --promote] [major|minor|patch]" >&2
    echo "" >&2
    echo "  (no args)                  pre-release, no new tag" >&2
    echo "  --pre                       pre-release, no new tag" >&2
    echo "  --pre major|minor|patch     bump version, tag X.Y.Z-pre, no GitHub release" >&2
    echo "  major|minor|patch           bump version, tag X.Y.Z, create GitHub release" >&2
    echo "  --promote                   promote latest X.Y.Z-pre to a full release:" >&2
    echo "                              tag X.Y.Z (no bump, no -pre), create GitHub release" >&2
    exit 1
}

PRE=false
PROMOTE=false
BUMP=""
for arg in "$@"; do
    case "$arg" in
        --pre)               PRE=true ;;
        --promote)           PROMOTE=true ;;
        major|minor|patch)   BUMP="$arg" ;;
        -h|--help)           usage ;;
        *) echo "Unknown argument: $arg" >&2; usage ;;
    esac
done

# --promote stands alone: it reuses the existing pre-release version as-is.
if $PROMOTE && ( $PRE || [[ -n "$BUMP" ]] ); then
    echo "ERROR: --promote cannot be combined with --pre or a bump keyword." >&2
    usage
fi

# No dirty releases or pre-releases.
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree is not clean. Commit or stash changes first." >&2
    exit 1
fi

TAG=""
NEWVER=""

if $PROMOTE; then
    # Promote the highest existing X.Y.Z-pre tag to X.Y.Z (no bump, no suffix).
    LATESTPRE=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-pre$' | sort -V | tail -1)
    if [[ -z "$LATESTPRE" ]]; then
        echo "ERROR: no X.Y.Z-pre tag found to promote." >&2
        exit 1
    fi
    NEWVER="${LATESTPRE%-pre}"
    TAG="${NEWVER}"
    echo "Promoting pre-release ${LATESTPRE} to ${NEWVER}"
elif [[ -n "$BUMP" ]]; then
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
fi

if [[ -n "$TAG" ]]; then
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
# This covers both a bumped full release and a promoted pre-release.
# Idempotent and non-interactive: if the release already exists (e.g. a
# previous run failed mid-way), just (re)upload the assets; otherwise create
# it. Assets are attached by full path (gh resolves bare filenames relative
# to the cwd, not release/).
if $PROMOTE || ( ! $PRE && [[ -n "$BUMP" ]] ); then
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
