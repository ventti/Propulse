set -e
VERSION=$(git describe --tags --always --dirty)
CI_PROJECT_DIR=$(git rev-parse --show-toplevel)

./build-all-releases.sh
./Propulse --version
./generate-changelog.sh
./upload-releases.sh

git push

# upload to github
if [[ ${VERSION} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    gh release create v${VERSION}
    for file in "$CI_PROJECT_DIR"/release/Propulse-*.zip; do
        filename=$(basename "${file}")
        gh release upload v${VERSION} "${filename}"
    done
fi

