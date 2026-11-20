#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP_NAME="FilePlus"
APP="$BUILD/$APP_NAME.app"
DMG="$BUILD/$APP_NAME.dmg"
VOLUME="Файл+"

if [[ ! -d "$APP" ]]; then
  "$ROOT/Scripts/build.sh"
fi

echo "→ Сборка DMG…"
rm -f "$DMG"
rm -rf "$BUILD/dmg"
mkdir -p "$BUILD/dmg"
cp -R "$APP" "$BUILD/dmg/"
ln -s /Applications "$BUILD/dmg/Applications"

hdiutil create \
  -volname "$VOLUME" \
  -srcfolder "$BUILD/dmg" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$BUILD/dmg"
echo "✓ DMG: $DMG"
echo ""
echo "Для раздачи другим пользователям подпишите и нотаризуйте (нужен Apple Developer ID):"
echo "  codesign --force --deep --options runtime --sign \"Developer ID Application: …\" \"$APP\""
echo "  xcrun notarytool submit \"$DMG\" --apple-id … --team-id … --password … --wait"
echo "  xcrun stapler staple \"$DMG\""
