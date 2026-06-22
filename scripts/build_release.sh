#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || echo "0.1.0")}"
if [[ -z "$VERSION" ]]; then
  VERSION="0.1.0"
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo "1")}"
APP_BUNDLE="$ROOT_DIR/dist/Lexi.app"
RELEASE_DIR="$ROOT_DIR/releases"
ZIP_PATH="$RELEASE_DIR/Lexi-$VERSION-$BUILD_NUMBER.zip"
NOTARIZE="${NOTARIZE:-0}"

mkdir -p "$RELEASE_DIR"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" "$ROOT_DIR/scripts/package_app.sh"

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
    echo "NOTARIZE=1 requires APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD." >&2
    exit 1
  fi
  if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
    echo "NOTARIZE=1 requires SIGN_IDENTITY to be a Developer ID Application certificate." >&2
    exit 1
  fi
  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP_BUNDLE"
fi

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

codesign --verify --deep --strict "$APP_BUNDLE"
echo "Release archive: $ZIP_PATH"
