#!/bin/bash

PROPULSE="$PWD/Propulse"
VERSION_URL="https://www.dropbox.com/scl/fi/qls23vtmsb1bff3jjjhwx/version.txt?rlkey=og28di232duaelbg8ak2xn74t&st=o6h9f6qz&dl=0"
VERSION_FILE=$(mktemp -t propulse-version.XXXXXX)
trap "rm -f $VERSION_FILE" EXIT

curl -L -o "$VERSION_FILE" "$VERSION_URL" || { echo "Failed to download version file"; exit 1; }

LATEST_VERSION=$(cat "$VERSION_FILE")
BUILD_VERSION=$($PROPULSE --build-version | tr -d '\r')

echo "Latest version: $LATEST_VERSION"
echo "Build version: $BUILD_VERSION"

if [ "$BUILD_VERSION" != "$LATEST_VERSION" ]; then
	echo "Update available"
else
	echo "No update available"
fi

rm -f "$VERSION_FILE"