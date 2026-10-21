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
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_app_updates.swift -o "$BUILD_DIR/HanAppUpdateChecks"
"$BUILD_DIR/HanAppUpdateChecks"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_search_habits.swift -o "$BUILD_DIR/HanSearchHabitChecks"
"$BUILD_DIR/HanSearchHabitChecks"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_document_search.swift -o "$BUILD_DIR/HanDocumentSearchChecks"
"$BUILD_DIR/HanDocumentSearchChecks"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_persistent_index.swift -o "$BUILD_DIR/HanPersistentIndexChecks"
"$BUILD_DIR/HanPersistentIndexChecks"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_launcher_reopen.swift -o "$BUILD_DIR/HanLauncherReopenChecks"
"$BUILD_DIR/HanLauncherReopenChecks"
swiftc -parse-as-library Sources/HanSearch/Services/OnboardingProgress.swift script/check_onboarding.swift -o "$BUILD_DIR/HanOnboardingChecks"
"$BUILD_DIR/HanOnboardingChecks"
swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_taiwan_search.swift -o "$BUILD_DIR/HanTaiwanSearchChecks"
"$BUILD_DIR/HanTaiwanSearchChecks"

swiftc -parse-as-library -I "$BUILD_DIR/Modules" \
  "$BUILD_DIR"/HanSearchCore.build/*.o \
  Sources/HanSearch/Services/*.swift Sources/HanSearch/Stores/*.swift \
  script/check_ocr_store.swift -o "$BUILD_DIR/HanOCRStoreChecks"
"$BUILD_DIR/HanOCRStoreChecks"
