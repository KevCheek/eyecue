#!/bin/bash
# Builds the zip people download: a universal, ad-hoc signed app, plus its SHA-256.
#   VERSION=0.2.0 scripts/package-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.2.0}"
UNIVERSAL=1 VERSION="$VERSION" scripts/build-app.sh
APP="build/Snowpine Cue.app"
lipo -archs "$APP/Contents/MacOS/SnowpineCue" | grep -q x86_64
lipo -archs "$APP/Contents/MacOS/SnowpineCue" | grep -q arm64
"$APP/Contents/MacOS/SnowpineCue" --launch-check
ZIP="build/Snowpine-Cue-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "Packaged $ZIP"
