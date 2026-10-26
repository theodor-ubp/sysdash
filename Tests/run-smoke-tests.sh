#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/sysdash-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -O "$PROJECT_DIR/sysdashv1/SystemMonitor.swift" \
    "$PROJECT_DIR/Tests/MonitorSmokeTests.swift" -o "$TEST_DIR/monitor-smoke-tests"
"$TEST_DIR/monitor-smoke-tests" "${1:-$PROJECT_DIR/sysdashv1/macmon}" "$PROJECT_DIR/Tests/Fixtures"
