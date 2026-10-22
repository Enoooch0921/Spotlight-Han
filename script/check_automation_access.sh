#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
swift build
BUILD_DIR="$(swift build --show-bin-path)"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_automation_access.swift -o "$BUILD_DIR/HanAutomationAccessChecks"
"$BUILD_DIR/HanAutomationAccessChecks"
