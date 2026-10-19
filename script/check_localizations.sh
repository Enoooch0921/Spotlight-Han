#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/work"
CHECK_DIR="$(mktemp -d "$ROOT_DIR/work/localization-check.XXXXXX")"
CHECK_APP="$CHECK_DIR/LocalizationChecks.app"
mkdir -p "$CHECK_APP/Contents/MacOS" "$CHECK_APP/Contents/Resources"
cp -R "$ROOT_DIR/Sources/HanSearch/Resources/". "$CHECK_APP/Contents/Resources/"
cat > "$CHECK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.hansearch.localizationchecks</string>
<key>CFBundleExecutable</key><string>LocalizationChecks</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hant</string>
</dict></plist>
PLIST
swiftc -parse-as-library "$ROOT_DIR/Sources/HanSearchCore/ChineseSearch.swift" "$ROOT_DIR/Sources/HanSearch/Services/AppLocalization.swift" "$ROOT_DIR/script/check_localizations.swift" -o "$CHECK_APP/Contents/MacOS/LocalizationChecks"
"$CHECK_APP/Contents/MacOS/LocalizationChecks"
