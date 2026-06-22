#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_PATH="${BUILD_PATH:-/tmp/lexi-swift-build}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Lexi"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.jeremyro.lexi}"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || echo "0.1.0")}"
if [[ -z "$VERSION" ]]; then
  VERSION="0.1.0"
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo "1")}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ICON_SOURCE="${ICON_SOURCE:-$ROOT_DIR/assets/Lexi.icns}"
ICON_FILE_NAME="Lexi.icns"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$BUILD_PATH/$CONFIGURATION/$APP_NAME"

swift build \
  --package-path "$ROOT_DIR" \
  --build-path "$BUILD_PATH" \
  --configuration "$CONFIGURATION"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RESOURCES_DIR/$ICON_FILE_NAME"
else
  echo "Warning: app icon not found at $ICON_SOURCE" >&2
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>Lexi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Jeremy Rodden. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
fi
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Packaged $APP_BUNDLE"
echo "Version $VERSION ($BUILD_NUMBER)"
echo "Signing identity: $SIGN_IDENTITY"
