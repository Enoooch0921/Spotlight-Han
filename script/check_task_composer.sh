#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
swift build
BUILD_DIR="$(swift build --show-bin-path)"
mkdir -p work
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_task_composer.swift -o "$BUILD_DIR/HanTaskComposerChecks"
"$BUILD_DIR/HanTaskComposerChecks"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_source_refresh.swift -o "$BUILD_DIR/HanSourceRefreshChecks"
"$BUILD_DIR/HanSourceRefreshChecks"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_app_library.swift -o "$BUILD_DIR/HanAppLibraryChecks"
"$BUILD_DIR/HanAppLibraryChecks"
