import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private var favoritesTable: NSTableView!
    private var accessibilityLabel: NSTextField!
    private var showFloatCheck: NSButton!
    private var opaqueFloatCheck: NSButton!
    private var interceptCheck: NSButton!
    private var hotkeyCheck: NSButton!
    private var hotkeyButton: NSButton!
    private var postPopup: NSPopUpButton!
    private var presetPopup: NSPopUpButton!
    private var isRecordingHotkey = false
    private var keyMonitor: Any?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки Файл+"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = buildContent()
        reload()
        NotificationCenter.default.addObserver(
            forName: .filePlusPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        reload()
    }

    private func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 580))
        var y: CGFloat = 540

        let title = NSTextField(labelWithString: "Файл+")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.frame = NSRect(x: 20, y: y, width: 300, height: 24)
        root.addSubview(title)
        y -= 34

        showFloatCheck = NSButton(checkboxWithTitle: "Плавающая кнопка ＋", target: self, action: #selector(toggleShowFloat))
        showFloatCheck.frame = NSRect(x: 20, y: y, width: 240, height: 22)
        root.addSubview(showFloatCheck)

        opaqueFloatCheck = NSButton(checkboxWithTitle: "Полупрозрачный фон кнопки", target: self, action: #selector(toggleOpaqueFloat))
        opaqueFloatCheck.frame = NSRect(x: 270, y: y, width: 250, height: 22)
        root.addSubview(opaqueFloatCheck)
        y -= 26

        interceptCheck = NSButton(checkboxWithTitle: "Перехват ПКМ на рабочем столе", target: self, action: #selector(toggleIntercept))
        interceptCheck.frame = NSRect(x: 20, y: y, width: 280, height: 22)
        root.addSubview(interceptCheck)
        y -= 28

        hotkeyCheck = NSButton(checkboxWithTitle: "Глобальный хоткей", target: self, action: #selector(toggleHotkey))
        hotkeyCheck.frame = NSRect(x: 20, y: y, width: 160, height: 22)
        root.addSubview(hotkeyCheck)

        hotkeyButton = NSButton(title: "⌥⌘N", target: self, action: #selector(startHotkeyRecording))
        hotkeyButton.bezelStyle = .rounded
        hotkeyButton.frame = NSRect(x: 190, y: y - 3, width: 120, height: 26)
        root.addSubview(hotkeyButton)

        let resetHotkey = NSButton(title: "Сброс", target: self, action: #selector(resetHotkey))
        resetHotkey.bezelStyle = .rounded
        resetHotkey.frame = NSRect(x: 320, y: y - 3, width: 70, height: 26)
        root.addSubview(resetHotkey)
        y -= 32

        let postLabel = NSTextField(labelWithString: "После создания:")
        postLabel.frame = NSRect(x: 20, y: y, width: 120, height: 22)
        root.addSubview(postLabel)
        postPopup = NSPopUpButton(frame: NSRect(x: 140, y: y - 2, width: 260, height: 26))
        for action in PostCreateAction.allCases {
            postPopup.addItem(withTitle: action.title)
            postPopup.lastItem?.representedObject = action.rawValue
        }
        postPopup.target = self
        postPopup.action = #selector(postChanged)
        root.addSubview(postPopup)
        y -= 32

        let presetLabel = NSTextField(labelWithString: "Пресет избранного:")
        presetLabel.frame = NSRect(x: 20, y: y, width: 140, height: 22)
        root.addSubview(presetLabel)
        presetPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 180, height: 26))
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        root.addSubview(presetPopup)

        let savePreset = NSButton(title: "Сохранить…", target: self, action: #selector(savePreset))
        savePreset.bezelStyle = .rounded
        savePreset.frame = NSRect(x: 350, y: y - 3, width: 100, height: 26)
        root.addSubview(savePreset)

        let deletePreset = NSButton(title: "Удалить", target: self, action: #selector(deleteSelectedPreset))
        deletePreset.bezelStyle = .rounded
        deletePreset.frame = NSRect(x: 455, y: y - 3, width: 70, height: 26)
        root.addSubview(deletePreset)
        y -= 32

        accessibilityLabel = NSTextField(labelWithString: "")
        accessibilityLabel.frame = NSRect(x: 20, y: y, width: 360, height: 22)
        accessibilityLabel.textColor = .secondaryLabelColor
        root.addSubview(accessibilityLabel)
        let axButton = NSButton(title: "Системные настройки…", target: self, action: #selector(openAccessibility))
        axButton.bezelStyle = .rounded
        axButton.frame = NSRect(x: 380, y: y - 2, width: 140, height: 26)
        root.addSubview(axButton)
        y -= 34

        let favLabel = NSTextField(labelWithString: "Избранные форматы (галочка = в меню)")
        favLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        favLabel.frame = NSRect(x: 20, y: y, width: 400, height: 20)
        root.addSubview(favLabel)
        y -= 8

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 70, width: 500, height: y - 70))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true

        favoritesTable = NSTableView(frame: scroll.bounds)
        favoritesTable.headerView = nil
        favoritesTable.rowHeight = 24
        favoritesTable.allowsMultipleSelection = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("fav"))
        col.width = 480
        favoritesTable.addTableColumn(col)
        favoritesTable.dataSource = self
        favoritesTable.delegate = self
        scroll.documentView = favoritesTable
        root.addSubview(scroll)

        let openTemplates = NSButton(title: "Открыть папку шаблонов", target: self, action: #selector(openTemplatesFolder))
        openTemplates.bezelStyle = .rounded
        openTemplates.frame = NSRect(x: 20, y: 28, width: 200, height: 28)
        root.addSubview(openTemplates)

        let reset = NSButton(title: "Сбросить избранное", target: self, action: #selector(resetFavorites))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 230, y: 28, width: 160, height: 28)
        root.addSubview(reset)

        let hint = NSTextField(wrappingLabelWithString: "Свои шаблоны в Templates. Переменные: {{date}}, {{time}}, {{name}}. Rename в Finder нужен Универсальный доступ.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 20, y: 6, width: 500, height: 20)
        root.addSubview(hint)

        return root
    }

    private func reload() {
        showFloatCheck?.state = AppPreferences.showFloatingButton ? .on : .off
        opaqueFloatCheck?.state = AppPreferences.floatingButtonOpaque ? .on : .off
        interceptCheck?.state = AppPreferences.interceptDesktopClick ? .on : .off
        hotkeyCheck?.state = AppPreferences.hotkeyEnabled ? .on : .off
        if !isRecordingHotkey {
            hotkeyButton?.title = AppPreferences.hotKey.displayString
        }

        let action = AppPreferences.postCreateAction
        if let idx = PostCreateAction.allCases.firstIndex(of: action) {
            postPopup?.selectItem(at: idx)
        }

        reloadPresets()

        let trusted = AXIsProcessTrusted()
        accessibilityLabel?.stringValue = trusted
            ? "Универсальный доступ: разрешён"
            : "Универсальный доступ: не выдан (ПКМ и rename)"

        favoritesTable?.reloadData()
    }

    private func reloadPresets() {
        presetPopup?.removeAllItems()
        let presets = AppPreferences.allPresets
        for preset in presets {
            presetPopup?.addItem(withTitle: preset.name)
            presetPopup?.lastItem?.representedObject = preset.id
        }
        if AppPreferences.activePresetId == "custom" || !presets.contains(where: { $0.id == AppPreferences.activePresetId }) {
            presetPopup?.addItem(withTitle: "Свой набор")
            presetPopup?.lastItem?.representedObject = "custom"
            presetPopup?.selectItem(at: (presetPopup?.numberOfItems ?? 1) - 1)
        } else if let idx = presets.firstIndex(where: { $0.id == AppPreferences.activePresetId }) {
            presetPopup?.selectItem(at: idx)
        }
    }

    @objc private func toggleShowFloat() {
        AppPreferences.showFloatingButton = showFloatCheck.state == .on
        DesktopClickMonitor.shared.applyPreferences()
    }

    @objc private func toggleOpaqueFloat() {
        AppPreferences.floatingButtonOpaque = opaqueFloatCheck.state == .on
        DesktopClickMonitor.shared.applyPreferences()
    }

    @objc private func toggleIntercept() {
        AppPreferences.interceptDesktopClick = interceptCheck.state == .on
        DesktopClickMonitor.shared.applyPreferences()
    }

    @objc private func toggleHotkey() {
        AppPreferences.hotkeyEnabled = hotkeyCheck.state == .on
        HotkeyManager.shared.applyPreferences()
    }

    @objc private func startHotkeyRecording() {
        isRecordingHotkey = true
        hotkeyButton.title = "Нажмите…"
        window?.makeFirstResponder(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecordingHotkey else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.stopHotkeyRecording(keep: false)
                return nil
            }
            if let config = HotKeyConfig.from(nsEvent: event) {
                AppPreferences.hotKey = config
                HotkeyManager.shared.applyPreferences()
                self.stopHotkeyRecording(keep: true)
                return nil
            }
            return nil
        }
    }

    private func stopHotkeyRecording(keep: Bool) {
        isRecordingHotkey = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        hotkeyButton.title = AppPreferences.hotKey.displayString
        _ = keep
    }

    @objc private func resetHotkey() {
        AppPreferences.hotKey = .default
        HotkeyManager.shared.applyPreferences()
        hotkeyButton.title = AppPreferences.hotKey.displayString
    }

    @objc private func postChanged() {
        guard let raw = postPopup.selectedItem?.representedObject as? String,
              let action = PostCreateAction(rawValue: raw)
        else { return }
        AppPreferences.postCreateAction = action
    }

    @objc private func presetChanged() {
        guard let id = presetPopup.selectedItem?.representedObject as? String,
              id != "custom",
              let preset = AppPreferences.allPresets.first(where: { $0.id == id })
        else { return }
        AppPreferences.applyPreset(preset)
        favoritesTable.reloadData()
    }

    @objc private func savePreset() {
        let alert = NSAlert()
        alert.messageText = "Сохранить пресет"
        alert.informativeText = "Имя набора избранных форматов"
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = "Мой набор"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AppPreferences.saveCurrentAsPreset(name: field.stringValue)
        reloadPresets()
    }

    @objc private func deleteSelectedPreset() {
        guard let id = presetPopup.selectedItem?.representedObject as? String,
              let preset = AppPreferences.allPresets.first(where: { $0.id == id }),
              !preset.isBuiltIn
        else {
            let alert = NSAlert()
            alert.messageText = "Нельзя удалить"
            alert.informativeText = "Встроенные пресеты удалить нельзя. Выберите свой набор."
            alert.runModal()
            return
        }
        AppPreferences.deletePreset(id: id)
        reloadPresets()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openTemplatesFolder() {
        AppSupport.ensureDirectories()
        NSWorkspace.shared.open(AppSupport.templatesURL)
    }

    @objc private func resetFavorites() {
        if let preset = AppPreferences.builtInPresets.first(where: { $0.id == "builtin.default" }) {
            AppPreferences.applyPreset(preset)
        } else {
            AppPreferences.favoriteTemplateIds = AppPreferences.defaultFavoriteIds
        }
        favoritesTable.reloadData()
        reloadPresets()
    }
}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        FileTemplates.all.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let templates = FileTemplates.all
        guard row < templates.count else { return nil }
        let template = templates[row]

        let cell = NSTableCellView()
        let check = NSButton(checkboxWithTitle: template.displayName, target: self, action: #selector(favoriteToggled(_:)))
        check.state = AppPreferences.isFavorite(template.id) ? .on : .off
        check.tag = row
        check.frame = NSRect(x: 4, y: 1, width: 470, height: 22)
        cell.addSubview(check)
        return cell
    }

    @objc private func favoriteToggled(_ sender: NSButton) {
        let templates = FileTemplates.all
        guard sender.tag >= 0, sender.tag < templates.count else { return }
        let id = templates[sender.tag].id
        let wantOn = sender.state == .on
        if wantOn != AppPreferences.isFavorite(id) {
            AppPreferences.toggleFavorite(id)
        }
        sender.state = AppPreferences.isFavorite(id) ? .on : .off
        favoritesTable.reloadData()
        reloadPresets()
    }
}
