#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/sysdash-updater.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -target arm64-apple-macosx12.4 "$PROJECT_DIR/sysdashv1/UpdateChecker.swift" \
    "$PROJECT_DIR/Tests/UpdateCheckerTests.swift" -o "$TEST_DIR/update-checker-tests"
"$TEST_DIR/update-checker-tests" "$@"
