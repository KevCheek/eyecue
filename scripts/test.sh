#!/bin/bash
# Runs every check: unit tests, the no-network check, and the app smoke test.
set -euo pipefail
cd "$(dirname "$0")/.."

# With only the Command Line Tools installed (no Xcode), SwiftPM may not find the
# Swift Testing macro plugin; point it there explicitly when it exists.
EXTRA=()
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [ -d "$PLUGINS" ] && ! xcode-select -p | grep -q Xcode.app; then
    EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi

swift test ${EXTRA[@]+"${EXTRA[@]}"}  # safe when empty on the Bash 3.2 macOS ships
scripts/check-no-network.sh
swift build
OUT="${TMPDIR:-/tmp}/snowpine-cue-smoke"
"$(swift build --show-bin-path)/SnowpineCue" --smoke-test "$OUT"
"$(swift build --show-bin-path)/SnowpineCue" --window-check
