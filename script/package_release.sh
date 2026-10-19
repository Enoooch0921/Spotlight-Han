#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/work" "$ROOT_DIR/outputs/releases"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/work/release-staging.XXXXXX")"
APP_BUNDLE="$STAGING_DIR/Spotlight Han.app"

# Build in a separate bundle, preserving the app currently running on this Mac.
HANSEARCH_BUILD_CONFIGURATION=release HANSEARCH_APP_BUNDLE="$APP_BUNDLE" \
  "$ROOT_DIR/script/build_and_run.sh" --build-only
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")"
ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_BUNDLE/Contents/MacOS/HanSearch")"
case "$ARCHITECTURES" in
  arm64) ARCHIVE_ARCH=arm64 ;;
  x86_64) ARCHIVE_ARCH=x86_64 ;;
  'x86_64 arm64'|'arm64 x86_64') ARCHIVE_ARCH=universal ;;
  *) echo "Unsupported architecture set: $ARCHITECTURES" >&2; exit 1 ;;
esac
RELEASE_DIR="$ROOT_DIR/outputs/releases/v$VERSION-$ARCHIVE_ARCH"
mkdir -p "$RELEASE_DIR"
ARCHIVE_NAME="Spotlight-Han-$VERSION-macOS-$ARCHIVE_ARCH.zip"
/usr/bin/ditto --norsrc --noextattr --noqtn -c -k --keepParent "$APP_BUNDLE" "$RELEASE_DIR/$ARCHIVE_NAME"
cp "$ROOT_DIR/docs/install.zh-Hant.md" "$RELEASE_DIR/INSTALL.zh-Hant.md"
DMG_NAME="Spotlight-Han-$VERSION-macOS-$ARCHIVE_ARCH.dmg"
DMG_CONTENTS="$STAGING_DIR/dmg"
mkdir -p "$DMG_CONTENTS"
/usr/bin/ditto --norsrc --noextattr --noqtn "$APP_BUNDLE" "$DMG_CONTENTS/Spotlight Han.app"
ln -s /Applications "$DMG_CONTENTS/Applications"
cp "$ROOT_DIR/docs/install.zh-Hant.md" "$DMG_CONTENTS/INSTALL.zh-Hant.md"
/usr/bin/hdiutil create -quiet -ov -volname "Spotlight Han" -srcfolder "$DMG_CONTENTS" -format UDZO "$RELEASE_DIR/$DMG_NAME"
/usr/bin/hdiutil verify -quiet "$RELEASE_DIR/$DMG_NAME"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$ARCHIVE_NAME" "$DMG_NAME" INSTALL.zh-Hant.md > SHA256SUMS.txt
)
echo "Release archive: $RELEASE_DIR/$ARCHIVE_NAME"
echo "Drag-to-Applications disk image: $RELEASE_DIR/$DMG_NAME"
echo "Signing status follows; notarization must be completed separately for a trusted public distribution."
/usr/bin/codesign -dvv "$APP_BUNDLE"
