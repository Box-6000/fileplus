#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
# ASCII-имя пакета (pluginkit/пути), отображаемое имя — «Файл+» из Info.plist
APP_NAME="FilePlus"
APP="$BUILD/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
PLUGINS="$APP/Contents/PlugIns"
APPEX="$PLUGINS/FilePlusFinderSync.appex"
APPEX_MACOS="$APPEX/Contents/MacOS"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) TARGET="arm64-apple-macos13.0" ;;
  x86_64) TARGET="x86_64-apple-macos13.0" ;;
  *) echo "Unknown arch $ARCH"; exit 1 ;;
esac
SDK="$(xcrun --show-sdk-path)"

echo "→ Сборка Файл+ ($ARCH)…"
rm -rf "$BUILD"
mkdir -p "$MACOS" "$RESOURCES" "$APPEX_MACOS"

swiftc -O -parse-as-library \
  -target "$TARGET" -sdk "$SDK" \
  -framework AppKit \
  -framework Carbon \
  -framework ApplicationServices \
  -o "$MACOS/FilePlus" \
  "$ROOT/Sources/App/"*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
mkdir -p "$RESOURCES/templates"
cp "$ROOT/Resources/templates/"*.docx "$RESOURCES/templates/" 2>/dev/null || true
cp "$ROOT/Resources/templates/"*.xlsx "$RESOURCES/templates/" 2>/dev/null || true
cp "$ROOT/Resources/templates/"*.pptx "$RESOURCES/templates/" 2>/dev/null || true
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Finder Sync (на системах с поддержкой; иначе работает DesktopClickMonitor)
swiftc -O \
  -target "$TARGET" -sdk "$SDK" \
  -module-name FilePlusFinderSync \
  -framework Cocoa \
  -framework FinderSync \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX_MACOS/FilePlusFinderSync" \
  "$ROOT/Sources/FinderSync/FinderSync.swift"

python3 <<PY
import plistlib
from pathlib import Path
info = plistlib.loads(Path("$ROOT/Sources/FinderSync/Info.plist").read_bytes())
info["NSExtension"]["NSExtensionPrincipalClass"] = "FilePlusFinderSync.FinderSync"
Path("$APPEX/Contents/Info.plist").write_bytes(plistlib.dumps(info))
PY

ENTITLEMENTS="$ROOT/Sources/FinderSync/FilePlusFinderSync.entitlements"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APPEX"
codesign --force --deep --sign - "$APP"

echo "✓ Собран: $APP"
