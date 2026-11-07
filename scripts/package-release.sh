#!/bin/bash
# Builds the zip people download: a universal app signed with SIGN_IDENTITY (ad-hoc without it), plus its SHA-256.
#   VERSION=0.3.0 scripts/package-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.3.0}"
UNIVERSAL=1 VERSION="$VERSION" scripts/build-app.sh
APP="build/Products.noindex/Snowpine Cue.app"
lipo -archs "$APP/Contents/MacOS/SnowpineCue" | grep -q x86_64
lipo -archs "$APP/Contents/MacOS/SnowpineCue" | grep -q arm64
"$APP/Contents/MacOS/SnowpineCue" --launch-check
# A fixed name, so .../releases/latest/download/Snowpine-Cue.zip always gets the newest version.
ZIP="build/Snowpine-Cue.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "Packaged $ZIP ($VERSION)"
