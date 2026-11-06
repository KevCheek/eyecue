#!/bin/bash
# Fails if the app code gains a way to reach the network, or if speech
# recognition stops being on-device only. These back the privacy promise in the README.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
if grep -rnE "URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|import Network|WKWebView|CFSocket|CFStream|SocketPort" Sources/; then
    echo "A networking API appears in Sources/. Snowpine Cue promises no network access." >&2
    fail=1
fi
if ! grep -q "requiresOnDeviceRecognition = true" Sources/SnowpineCue/SpeechFollower.swift; then
    echo "Speech recognition must stay on-device (requiresOnDeviceRecognition = true)." >&2
    fail=1
fi
if grep -q "com.apple.security.network" Resources/SnowpineCue.entitlements; then
    echo "The entitlements file grants network access." >&2
    fail=1
fi
# The sandbox key must be present and true, not just mentioned.
if [ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" Resources/SnowpineCue.entitlements 2>/dev/null)" != "true" ]; then
    echo "The App Sandbox entitlement is missing or not true." >&2
    fail=1
fi
[ $fail -eq 0 ] && echo "No-network check passed"
exit $fail
