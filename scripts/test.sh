#!/bin/bash
# Runs the core unit tests. With Command Line Tools only (no Xcode), SwiftPM doesn't pass the
# swift-testing macro plugin path, so we add it explicitly.
set -e
cd "$(dirname "$0")/.."
PLUG="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
EXTRA=()
[ -d "$PLUG" ] && EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUG")
swift test "${EXTRA[@]}" "$@"
