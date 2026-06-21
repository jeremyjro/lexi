#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/Lexi.app"
INSTALL_PATH="${INSTALL_PATH:-/Applications/Lexi.app}"
ASSUME_YES="${ASSUME_YES:-0}"

"$ROOT_DIR/scripts/package_app.sh"

if [[ -e "$INSTALL_PATH" && "$ASSUME_YES" != "1" ]]; then
  printf 'Replace %s? [y/N] ' "$INSTALL_PATH"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Install cancelled."; exit 1 ;;
  esac
fi

pkill -x Lexi 2>/dev/null || true
rm -rf "$INSTALL_PATH"
ditto "$SOURCE_APP" "$INSTALL_PATH"
codesign --verify --deep --strict "$INSTALL_PATH"
open "$INSTALL_PATH"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true

echo "Installed $INSTALL_PATH"
echo "If Accessibility capture does not work, remove old Lexi entries and enable Accessibility for this installed app."
