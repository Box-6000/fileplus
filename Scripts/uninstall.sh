#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_ID="com.konstantindzon.fileplus"
EXT_ID="com.konstantindzon.fileplus.FinderSync"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
echo "→ Удаление Файл+…"
launchctl bootout "gui/$(id -u)/$PLIST_ID" 2>/dev/null || true
pkill -x FilePlus 2>/dev/null || true
pkill -f "FilePlus.app/Contents/MacOS/FilePlus" 2>/dev/null || true
pkill -f "Файл+.app/Contents/MacOS/FilePlus" 2>/dev/null || true
pluginkit -e ignore -i "$EXT_ID" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$PLIST_ID.plist"
for app in \
  "/Applications/FilePlus.app" \
  "/Applications/Файл+.app" \
  "/Applications/New File Menu.app" \
  "$ROOT/build/FilePlus.app"
do
  if [[ -d "$app" ]]; then
    "$LSREGISTER" -u "$app" 2>/dev/null || true
  fi
done
rm -rf "/Applications/FilePlus.app" "/Applications/Файл+.app" "/Applications/New File Menu.app"
rm -rf "$HOME/Library/Services/Создать новый файл.workflow"
rm -rf "$HOME/Library/Services/Создать файл на рабочем столе.workflow"
rm -rf "$HOME/Library/Services/NewFileMenuService.app"
killall Finder 2>/dev/null || true
echo "✓ Удалено"
