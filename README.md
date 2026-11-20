# Файл+ (FilePlus)

macOS-утилита для быстрого создания файлов и папок: строка меню, плавающая кнопка **＋**, глобальный хоткей и (опционально) правый клик по рабочему столу.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Arch](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-2.2.0-orange)

## Возможности

- **Строка меню** — иконка `doc.badge.plus`, избранные и недавние форматы, все шаблоны
- **Плавающая кнопка ＋** — перетаскивается, видна при активном Finder; прозрачный или полупрозрачный фон
- **Глобальный хоткей** — по умолчанию `⌥⌘N`, комбинацию можно записать в настройках
- **Новая папка** — из меню или кнопки ＋
- **ПКМ на рабочем столе** — создание файла (нужен Универсальный доступ)
- **Finder Sync** — пункт «Новый файл» в контекстном меню Finder
- **Свои шаблоны** — любые файлы в Application Support + переменные `{{date}}`, `{{time}}`, `{{name}}`
- **Пресеты избранного** — Офис / Код / Текст / свои наборы
- **После создания** — показать и переименовать / показать в Finder / открыть / ничего

Поддерживаемые форматы из коробки: Word, Excel, PowerPoint, Markdown, HTML, JSON, Swift, Python, JS/TS, Shell и др.

## Требования

- macOS 13 Ventura или новее
- Apple Silicon или Intel (сборка под архитектуру машины)

## Быстрая установка

### Из релиза (DMG)

1. Скачайте `FilePlus.dmg` со страницы [Releases](../../releases)
2. Откройте DMG и перетащите **FilePlus** в **Applications**
3. Запустите приложение (при первом запуске без нотаризации: ПКМ → **Открыть**)

### Из исходников

```bash
git clone https://github.com/Box-6000/fileplus.git
cd fileplus
./Scripts/build.sh
./Scripts/install.sh
```

Сборка DMG:

```bash
./Scripts/build.sh
./Scripts/package-dmg.sh
# → build/FilePlus.dmg
```

Удаление:

```bash
./Scripts/uninstall.sh
```

## Использование

| Действие | Как |
|----------|-----|
| Создать файл | Меню в строке меню → формат или «Выбрать формат…» |
| В текущей папке Finder | Меню → «В текущей папке Finder…» или хоткей |
| Плавающая кнопка | Клик по **＋** (Finder должен быть активен) |
| Новая папка | Меню / кнопка ＋ → «Новая папка…» |
| ПКМ на рабочем столе | Включите в настройках + Универсальный доступ |
| Настройки | Меню → **Настройки…** (`⌘,`) |

### Свои шаблоны

Путь:

```text
~/Library/Application Support/FilePlus/Templates/
```

Любой файл в папке становится шаблоном. В текстовых шаблонах:

- `{{date}}` — `yyyy-MM-dd`
- `{{time}}` — `HH:mm`
- `{{name}}` — имя файла без расширения

Открыть папку: **Настройки…** → «Открыть папку шаблонов».

## Структура проекта

```text
Sources/
  App/                 # основное меню-бар приложение (AppKit + Swift)
  FinderSync/          # расширение Finder Sync
Resources/             # Info.plist, иконка, office-шаблоны
Scripts/
  build.sh             # сборка .app
  install.sh           # установка в /Applications + LaunchAgent
  uninstall.sh
  package-dmg.sh       # DMG для раздачи
```

Сборка через `swiftc` (без Xcode-проекта). Зависимости: AppKit, Carbon, ApplicationServices, FinderSync.

## Разрешения

| Разрешение | Зачем |
|------------|--------|
| Универсальный доступ | ПКМ на рабочем столе и «показать и переименовать» в Finder |
| LaunchAgent | автозапуск при входе в систему (ставит `install.sh`) |

## Подпись и нотаризация (опционально)

Для раздачи без предупреждения Gatekeeper нужен Apple Developer ID:

```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  build/FilePlus.app

./Scripts/package-dmg.sh

xcrun notarytool submit build/FilePlus.dmg \
  --apple-id "you@example.com" --team-id TEAMID --password "app-specific-password" --wait
xcrun stapler staple build/FilePlus.dmg
```

## Лицензия

MIT — см. [LICENSE](LICENSE).
