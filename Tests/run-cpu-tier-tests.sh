#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/sysdash-tiers.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc "$PROJECT_DIR/sysdashv1/SystemMonitor.swift" \
    "$PROJECT_DIR/Tests/CPUTierTests.swift" -o "$TEST_DIR/cpu-tier-tests"
"$TEST_DIR/cpu-tier-tests" "$PROJECT_DIR/Tests/Fixtures"
