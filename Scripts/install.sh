#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FilePlus"
DISPLAY="Файл+"
SRC="$ROOT/build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
PLIST_ID="com.konstantindzon.fileplus"
EXT_ID="com.konstantindzon.fileplus.FinderSync"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS/$PLIST_ID.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SRC" ]]; then
  "$ROOT/Scripts/build.sh"
fi

echo "→ Установка $DISPLAY…"

# Останавливаем все копии
for old in \
  "com.konstantindzon.newfilemenu" \
  "com.konstantindzon.fileplus"
do
  launchctl bootout "gui/$(id -u)/$old" 2>/dev/null || true
  rm -f "$LAUNCH_AGENTS/$old.plist"
done
pkill -x FilePlus 2>/dev/null || true
pkill -f "FilePlus.app/Contents/MacOS/FilePlus" 2>/dev/null || true
pkill -f "Файл+.app/Contents/MacOS/FilePlus" 2>/dev/null || true
sleep 0.3

# Удаляем старые приложения и снимаем их с регистрации Launch Services
for old_app in \
  "/Applications/New File Menu.app" \
  "/Applications/Файл+.app" \
  "$DEST" \
  "$SRC"
do
  if [[ -d "$old_app" ]]; then
    "$LSREGISTER" -u "$old_app" 2>/dev/null || true
  fi
done
rm -rf "/Applications/New File Menu.app" "/Applications/Файл+.app" "$DEST"

cp -R "$SRC" "$DEST"

# Сразу снимаем build-копию с регистрации — иначе в системе «два» Файл+
"$LSREGISTER" -u "$SRC" 2>/dev/null || true

# Не переподписываем каждый раз новым adhoc-хешем без нужды —
# иначе macOS сбрасывает выданные разрешения TCC.
if ! codesign --verify --quiet "$DEST" 2>/dev/null; then
  ENTITLEMENTS="$ROOT/Sources/FinderSync/FilePlusFinderSync.entitlements"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$DEST/Contents/PlugIns/FilePlusFinderSync.appex" 2>/dev/null || true
  codesign --force --deep --sign - "$DEST"
fi

"$LSREGISTER" -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/FilePlusFinderSync.appex" 2>/dev/null || true
pluginkit -e use -i "$EXT_ID" 2>/dev/null || true

mkdir -p "$LAUNCH_AGENTS"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$PLIST_ID</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DEST/Contents/MacOS/FilePlus</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null \
  || launchctl load "$PLIST_PATH" 2>/dev/null || true

sleep 0.5
# Один запуск: LaunchAgent или open — не оба сразу
if ! pgrep -x FilePlus >/dev/null; then
  open "$DEST"
  sleep 0.4
fi

# На всякий случай убиваем лишние процессы, если всплыл второй
COUNT="$(pgrep -x FilePlus | wc -l | tr -d ' ')"
if [[ "$COUNT" -gt 1 ]]; then
  echo "⚠ Найдено $COUNT процессов FilePlus — оставляем один"
  pgrep -x FilePlus | tail -n +2 | xargs kill 2>/dev/null || true
fi

killall Finder 2>/dev/null || true

echo ""
echo "✓ Установлено: $DEST (один экземпляр «$DISPLAY»)"
echo ""
echo "Создание файлов:"
echo "  • строка меню «Файл+»"
echo "  • плавающая кнопка ＋ (можно скрыть в меню)"
echo "  • ПКМ на рабочем столе — только если Универсальный доступ уже выдан"
echo ""
