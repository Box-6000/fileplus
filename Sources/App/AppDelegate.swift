import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var isCLIMode = false
    private var prefsObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        isCLIMode = args.contains("--create") || args.contains("--quick")

        NSApp.setActivationPolicy(.accessory)
        AppPreferences.bootstrap()

        if isCLIMode {
            handleLaunchArguments(args)
            return
        }

        setupStatusItem()
        DesktopClickMonitor.shared.start()
        HotkeyManager.shared.start()
        observePreferences()
        maybeShowOnboarding()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        DesktopClickMonitor.shared.stop()
        if let prefsObserver {
            NotificationCenter.default.removeObserver(prefsObserver)
        }
        if let activateObserver {
            NotificationCenter.default.removeObserver(activateObserver)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleURL(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentStatusMenu()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func observePreferences() {
        prefsObserver = NotificationCenter.default.addObserver(
            forName: .filePlusPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildMenu()
        }
        activateObserver = NotificationCenter.default.addObserver(
            forName: .filePlusActivateUI,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentStatusMenu()
        }
    }

    private func maybeShowOnboarding() {
        guard !AppPreferences.didShowOnboarding else { return }
        AppPreferences.didShowOnboarding = true
        guard AppPreferences.interceptDesktopClick, !AXIsProcessTrusted() else { return }

        let alert = NSAlert()
        alert.messageText = "Добро пожаловать в Файл+"
        alert.informativeText = """
        Плавающая кнопка ＋ и меню в строке меню уже работают.

        Для создания файла правым кликом по пустому месту на рабочем столе нужен Универсальный доступ (Системные настройки → Конфиденциальность).

        Свои шаблоны: Настройки → «Открыть папку шаблонов».
        Хоткей (по умолчанию ⌥⌘N) — создать файл в текущей папке Finder; меняется в Настройках.
        После создания можно сразу переименовать в Finder (если выдан доступ).
        """
        alert.addButton(withTitle: "Открыть настройки доступа")
        alert.addButton(withTitle: "Позже")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "Файл+")?
                .withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
                button.title = ""
            } else {
                button.title = "Файл+"
            }
            button.toolTip = "Файл+ — создать файл (\(AppPreferences.hotKey.displayString))"
        }
        statusItem = item
        rebuildMenu()
    }

    func presentStatusMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        statusItem.button?.performClick(nil)
        _ = button
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let choose = NSMenuItem(title: "Выбрать формат…", action: #selector(createDesktop), keyEquivalent: "n")
        choose.keyEquivalentModifierMask = [.command]
        choose.target = self
        menu.addItem(choose)

        let here = NSMenuItem(title: "В текущей папке Finder…", action: #selector(createHere), keyEquivalent: "")
        here.target = self
        menu.addItem(here)

        let folder = NSMenuItem(title: "Новая папка…", action: #selector(createFolderHere), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)
        menu.addItem(.separator())

        let recent = AppPreferences.recentTemplates
        if !recent.isEmpty {
            let head = NSMenuItem(title: "Недавние", action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
            for template in recent {
                let mi = NSMenuItem(title: template.displayName, action: #selector(createTypedOnDesktop(_:)), keyEquivalent: "")
                mi.representedObject = template.id
                mi.target = self
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }

        for template in AppPreferences.favoriteTemplates {
            let mi = NSMenuItem(title: template.displayName, action: #selector(createTypedOnDesktop(_:)), keyEquivalent: "")
            mi.representedObject = template.id
            mi.target = self
            menu.addItem(mi)
        }

        let allFormats = NSMenuItem(title: "Все форматы", action: nil, keyEquivalent: "")
        let allSub = NSMenu()
        for template in FileTemplates.all {
            let mi = NSMenuItem(title: template.displayName, action: #selector(createTypedOnDesktop(_:)), keyEquivalent: "")
            mi.representedObject = template.id
            mi.target = self
            allSub.addItem(mi)
        }
        allFormats.submenu = allSub
        menu.addItem(allFormats)

        let presetsRoot = NSMenuItem(title: "Пресет избранного", action: nil, keyEquivalent: "")
        let presetsSub = NSMenu()
        for preset in AppPreferences.allPresets {
            let mi = NSMenuItem(title: preset.name, action: #selector(applyPreset(_:)), keyEquivalent: "")
            mi.representedObject = preset.id
            mi.target = self
            mi.state = AppPreferences.activePresetId == preset.id ? .on : .off
            presetsSub.addItem(mi)
        }
        presetsRoot.submenu = presetsSub
        menu.addItem(presetsRoot)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Настройки…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.toolTip = "Файл+ — создать файл (\(AppPreferences.hotKey.displayString))"
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func createDesktop() {
        FileCreator.promptAndCreate(in: FileCreator.desktopDirectory())
    }

    @objc private func createHere() {
        FileCreator.promptAndCreate(in: FileCreator.finderInsertionDirectory())
    }

    @objc private func createFolderHere() {
        FileCreator.promptAndCreateFolder(in: FileCreator.finderInsertionDirectory())
    }

    @objc private func createTypedOnDesktop(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        FileCreator.createQuick(templateId: id, in: FileCreator.desktopDirectory())
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = AppPreferences.allPresets.first(where: { $0.id == id })
        else { return }
        AppPreferences.applyPreset(preset)
    }

    private func finishCLIIfNeeded() {
        if isCLIMode {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func handleLaunchArguments(_ args: [String]) {
        if let idx = args.firstIndex(of: "--create"), args.indices.contains(idx + 1) {
            let dir = URL(fileURLWithPath: args[idx + 1])
            DispatchQueue.main.async {
                FileCreator.promptAndCreate(in: dir)
                self.finishCLIIfNeeded()
            }
            return
        }
        if let idx = args.firstIndex(of: "--quick"), args.indices.contains(idx + 2) {
            let templateId = args[idx + 1]
            let dir = URL(fileURLWithPath: args[idx + 2])
            DispatchQueue.main.async {
                FileCreator.createQuick(templateId: templateId, in: dir)
                self.finishCLIIfNeeded()
            }
            return
        }
        finishCLIIfNeeded()
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "fileplus" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let dirPath = items.first(where: { $0.name == "dir" })?.value.map { $0.removingPercentEncoding ?? $0 }
        let directory = dirPath.map { URL(fileURLWithPath: $0) } ?? FileCreator.desktopDirectory()
        DispatchQueue.main.async {
            if url.host == "quick", let id = items.first(where: { $0.name == "id" })?.value {
                FileCreator.createQuick(templateId: id, in: directory)
            } else {
                FileCreator.promptAndCreate(in: directory)
            }
        }
    }
}
