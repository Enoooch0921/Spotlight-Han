#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR"
APP_BUNDLE="$ROOT_DIR/outputs/Spotlight Han.app"
APP_NAME="HanSearch"

case "$MODE" in run|--verify|--debug|--logs|--telemetry|--build-only) ;; *) echo "Usage: $0 [run|--verify|--debug|--logs|--telemetry|--build-only]" >&2; exit 2 ;; esac
if [[ "$MODE" != "--build-only" ]]; then pkill -x "$APP_NAME" >/dev/null 2>&1 || true; fi
swift build --package-path "$PACKAGE_DIR"
BUILD_DIR="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ -f "$ROOT_DIR/Assets/SpotlightHan.icns" ]]; then cp "$ROOT_DIR/Assets/SpotlightHan.icns" "$APP_BUNDLE/Contents/Resources/SpotlightHan.icns"; fi
cp "$ROOT_DIR/Assets/Shortcuts/Spotlight-Han-System-Clock.shortcut" "$APP_BUNDLE/Contents/Resources/"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HanSearch</string>
<key>CFBundleIdentifier</key><string>local.hansearch.mac</string>
<key>CFBundleName</key><string>Spotlight Han</string>
<key>CFBundleDisplayName</key><string>Spotlight Han</string>
<key>CFBundleIconFile</key><string>SpotlightHan.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.2</string>
<key>CFBundleVersion</key><string>7</string>
<key>NSContactsUsageDescription</key><string>在本機搜尋你允許取用的聯絡人，不會上傳。</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>搜尋行事曆，並依你確認的指令新增行程。</string>
<key>NSRemindersFullAccessUsageDescription</key><string>搜尋提醒事項，並依你確認的指令新增提醒。</string>
<key>NSAppleEventsUsageDescription</key><string>讀取備忘錄與 Mail 的內容以供本機搜尋，或開啟你選擇的項目。</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$APP_BUNDLE"
case "$MODE" in
  --build-only) ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "HanSearch"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
