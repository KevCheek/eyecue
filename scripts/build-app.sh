#!/bin/bash
# Builds build/Products.noindex/Snowpine Cue.app: a sandboxed menu bar app with Sparkle for in-app updates, signed with
# SIGN_IDENTITY (the release certificate) or ad-hoc when that is not set.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  build, then move it to ~/Applications
# BUNDLE_ID and VERSION can be overridden from the environment. UNIVERSAL=1 builds for Apple silicon and Intel.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:-com.snowpinecode.cue}"
VERSION="${VERSION:-0.3.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

ARCHS=()
if [ "${UNIVERSAL:-}" = "1" ]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/SnowpineCue"

# Spotlight skips any folder whose name ends in .noindex, so a build never shows up as a second
# Snowpine Cue next to the installed one.
APP="build/Products.noindex/Snowpine Cue.app"
rm -rf "build/Snowpine Cue.app" "$APP"  # build/Snowpine Cue.app: where older builds went
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnowpineCue"
# The brand fonts (SIL Open Font License) travel with the app.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
# App icon: Resources/AppIcon.png (1024 x 1024) becomes AppIcon.icns.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Signing. SIGN_IDENTITY is the release certificate (CI imports it into SIGN_KEYCHAIN); without it the
# build is ad-hoc signed, which is fine for testing but makes macOS ask for permissions again after an update.
IDENTITY="${SIGN_IDENTITY:--}"
KEYCHAIN_ARGS=()
if [ -n "${SIGN_KEYCHAIN:-}" ]; then KEYCHAIN_ARGS=(--keychain "$SIGN_KEYCHAIN"); fi

# Sparkle (in-app updates) goes in first and is signed inside out.
scripts/embed-sparkle.sh "$APP" "$IDENTITY" "${SIGN_KEYCHAIN:-}"

# The app's entitlements, with the bundle id filled in for Sparkle's local service names.
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" Resources/SnowpineCue.entitlements > build/SnowpineCue.entitlements
codesign --force --options runtime --timestamp=none --entitlements build/SnowpineCue.entitlements \
    --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$APP"
codesign --verify --strict --deep "$APP"

# Check the entitlements actually signed into the app: sandbox on, no network, microphone and chosen
# files only, plus exactly Sparkle's two local service names.
SIGNED="build/signed-entitlements.plist"
codesign -d --entitlements - --xml "$APP" 2>/dev/null > "$SIGNED"
/usr/bin/python3 - "$SIGNED" "$BUNDLE_ID" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb")); bid = sys.argv[2]
want = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.device.audio-input": True,
    "com.apple.security.files.user-selected.read-only": True,
    "com.apple.security.cs.disable-library-validation": True,
    "com.apple.security.temporary-exception.mach-lookup.global-name": [bid + "-spks", bid + "-spki"],
}
if d != want:
    sys.exit("The signed app's entitlements are not exactly the expected set: %r" % d)
PY
# Sparkle's helpers keep Sparkle's own setup: no entitlements at all, on every architecture.
for part in XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app; do
    BINPATH="$APP/Contents/Frameworks/Sparkle.framework/Versions/B/$part"
    for arch in $(lipo -archs "$(find "$BINPATH/Contents/MacOS" -type f | head -1)"); do
        if codesign -d --entitlements - --xml --arch "$arch" "$BINPATH" 2>/dev/null | grep -q "<key>"; then
            echo "Sparkle's $part ($arch) must carry no entitlements." >&2
            exit 1
        fi
    done
done
for arch in $(lipo -archs "$APP/Contents/MacOS/SnowpineCue"); do
    codesign -d --entitlements - --xml --arch "$arch" "$APP" 2>/dev/null | cmp -s - "$SIGNED" \
        || { echo "The app's entitlements differ on $arch." >&2; exit 1; }
done
echo "Built $APP ($VERSION, $BUNDLE_ID)"

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Snowpine Cue.app"
    # Move rather than copy, so Spotlight finds one Snowpine Cue, not a second one in build/.
    mv "$APP" "$HOME/Applications/"
    echo "Installed ~/Applications/Snowpine Cue.app"
fi
