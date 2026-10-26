#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/sysdash-meters.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
SOURCES=()
for source in "$PROJECT_DIR/sysdashv1/"*.swift; do
    if [[ "$source" != */sysdashv1App.swift ]]; then SOURCES+=("$source"); fi
done
xcrun swiftc -O -target arm64-apple-macosx13.0 "${SOURCES[@]}" "$PROJECT_DIR/Tests/MeterContainmentTests.swift" -o "$TEST_DIR/meter-tests"
"$TEST_DIR/meter-tests"
