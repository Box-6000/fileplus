import Foundation
import AppKit
import Carbon.HIToolbox

enum PostCreateAction: String, CaseIterable {
    case revealAndRename
    case revealInFinder
    case openInApp
    case nothing

    var title: String {
        switch self {
        case .revealAndRename: return "Показать и переименовать"
        case .revealInFinder: return "Показать в Finder"
        case .openInApp: return "Открыть в приложении"
        case .nothing: return "Ничего"
        }
    }
}

struct HotKeyConfig: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(cmdKey | optionKey)
    )

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyCodeToGlyph(keyCode))
        return parts.joined()
    }

    private static func keyCodeToGlyph(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        return map[code] ?? "Key\(code)"
    }

    static func from(nsEvent event: NSEvent) -> HotKeyConfig? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        // Нужен хотя бы один модификатор (кроме одного Shift)
        let hasStrong = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        guard hasStrong else { return nil }
        return HotKeyConfig(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    }
}

struct FavoritePreset: Equatable {
    let id: String
    let name: String
    let templateIds: [String]
    let isBuiltIn: Bool
}

enum AppPreferences {
    private static let defaults = UserDefaults.standard
    private static let maxRecent = 8

    private enum Key {
        static let showFloatingButton = "fileplus.showFloatingButton"
        static let floatingOriginX = "fileplus.floatingOriginX"
        static let floatingOriginY = "fileplus.floatingOriginY"
        static let floatingButtonOpaque = "fileplus.floatingButtonOpaque"
        static let interceptDesktopClick = "fileplus.interceptDesktopClick"
        static let favoriteTemplateIds = "fileplus.favoriteTemplateIds"
        static let recentTemplateIds = "fileplus.recentTemplateIds"
        static let postCreateAction = "fileplus.postCreateAction"
        static let hotkeyEnabled = "fileplus.hotkeyEnabled"
        static let hotkeyKeyCode = "fileplus.hotkeyKeyCode"
        static let hotkeyModifiers = "fileplus.hotkeyModifiers"
        static let didShowOnboarding = "fileplus.didShowOnboarding"
        static let customPresets = "fileplus.customPresets"
        static let activePresetId = "fileplus.activePresetId"
    }

    static let defaultFavoriteIds = ["docx", "xlsx", "pptx", "txt", "md", "html", "py", "js", "json"]

    static let builtInPresets: [FavoritePreset] = [
        FavoritePreset(
            id: "builtin.office",
            name: "Офис",
            templateIds: ["docx", "xlsx", "pptx", "csv", "txt", "rtf"],
            isBuiltIn: true
        ),
        FavoritePreset(
            id: "builtin.code",
            name: "Код",
            templateIds: ["swift", "py", "js", "ts", "html", "css", "json", "md", "sh"],
            isBuiltIn: true
        ),
        FavoritePreset(
            id: "builtin.writing",
            name: "Текст",
            templateIds: ["md", "txt", "rtf", "html", "docx"],
            isBuiltIn: true
        ),
        FavoritePreset(
            id: "builtin.default",
            name: "По умолчанию",
            templateIds: defaultFavoriteIds,
            isBuiltIn: true
        ),
    ]

    static var showFloatingButton: Bool {
        get {
            if defaults.object(forKey: Key.showFloatingButton) == nil { return true }
            return defaults.bool(forKey: Key.showFloatingButton)
        }
        set {
            defaults.set(newValue, forKey: Key.showFloatingButton)
            NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
        }
    }

    static var floatingButtonOpaque: Bool {
        get {
            if defaults.object(forKey: Key.floatingButtonOpaque) == nil { return false }
            return defaults.bool(forKey: Key.floatingButtonOpaque)
        }
        set {
            defaults.set(newValue, forKey: Key.floatingButtonOpaque)
            NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
        }
    }

    static var interceptDesktopClick: Bool {
        get {
            if defaults.object(forKey: Key.interceptDesktopClick) == nil { return true }
            return defaults.bool(forKey: Key.interceptDesktopClick)
        }
        set {
            defaults.set(newValue, forKey: Key.interceptDesktopClick)
            NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
        }
    }

    static var hotkeyEnabled: Bool {
        get {
            if defaults.object(forKey: Key.hotkeyEnabled) == nil { return true }
            return defaults.bool(forKey: Key.hotkeyEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.hotkeyEnabled)
            NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
        }
    }

    static var hotKey: HotKeyConfig {
        get {
            if defaults.object(forKey: Key.hotkeyKeyCode) == nil {
                return .default
            }
            return HotKeyConfig(
                keyCode: UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers))
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotkeyModifiers)
            NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
        }
    }

    static var didShowOnboarding: Bool {
        get { defaults.bool(forKey: Key.didShowOnboarding) }
        set { defaults.set(newValue, forKey: Key.didShowOnboarding) }
    }

    static var floatingOrigin: NSPoint? {
        get {
            guard defaults.object(forKey: Key.floatingOriginX) != nil else { return nil }
            return NSPoint(
                x: defaults.double(forKey: Key.floatingOriginX),
                y: defaults.double(forKey: Key.floatingOriginY)
            )
        }
        set {
            if let newValue {
                defaults.set(newValue.x, forKey: Key.floatingOriginX)
                defaults.set(newValue.y, forKey: Key.floatingOriginY)
            } else {
                defaults.removeObject(forKey: Key.floatingOriginX)
                defaults.removeObject(forKey: Key.floatingOriginY)
            }
        }
    }

    static var postCreateAction: PostCreateAction {
        get {
            guard let raw = defaults.string(forKey: Key.postCreateAction),
                  let action = PostCreateAction(rawValue: raw)
            else { return .revealAndRename }
            return action
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.postCreateAction)
            NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
        }
    }

    static var favoriteTemplateIds: [String] {
        get {
            let stored = defaults.stringArray(forKey: Key.favoriteTemplateIds) ?? defaultFavoriteIds
            let valid = stored.filter { FileTemplates.template(id: $0) != nil }
            return valid.isEmpty ? defaultFavoriteIds.filter { FileTemplates.template(id: $0) != nil } : valid
        }
        set {
            let valid = newValue.filter { FileTemplates.template(id: $0) != nil }
            let ids = valid.isEmpty ? defaultFavoriteIds : valid
            defaults.set(ids, forKey: Key.favoriteTemplateIds)
            defaults.set("custom", forKey: Key.activePresetId)
            persistSharedState()
            NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
        }
    }

    static var recentTemplateIds: [String] {
        get {
            let stored = defaults.stringArray(forKey: Key.recentTemplateIds) ?? []
            return stored.filter { FileTemplates.template(id: $0) != nil }
        }
        set {
            let valid = Array(newValue.filter { FileTemplates.template(id: $0) != nil }.prefix(maxRecent))
            defaults.set(valid, forKey: Key.recentTemplateIds)
            persistSharedState()
        }
    }

    static var favoriteTemplates: [FileTemplate] {
        favoriteTemplateIds.compactMap { FileTemplates.template(id: $0) }
    }

    static var recentTemplates: [FileTemplate] {
        recentTemplateIds.compactMap { FileTemplates.template(id: $0) }
    }

    static var activePresetId: String {
        get { defaults.string(forKey: Key.activePresetId) ?? "builtin.default" }
        set { defaults.set(newValue, forKey: Key.activePresetId) }
    }

    static var allPresets: [FavoritePreset] {
        builtInPresets + loadCustomPresets()
    }

    static func isFavorite(_ id: String) -> Bool {
        favoriteTemplateIds.contains(id)
    }

    static func toggleFavorite(_ id: String) {
        guard FileTemplates.template(id: id) != nil else { return }
        var ids = favoriteTemplateIds
        if let index = ids.firstIndex(of: id) {
            if ids.count == 1 { return }
            ids.remove(at: index)
        } else {
            ids.append(id)
            let order = Dictionary(uniqueKeysWithValues: FileTemplates.all.enumerated().map { ($1.id, $0) })
            ids.sort { (order[$0] ?? 0) < (order[$1] ?? 0) }
        }
        favoriteTemplateIds = ids
    }

    static func applyPreset(_ preset: FavoritePreset) {
        let valid = preset.templateIds.filter { FileTemplates.template(id: $0) != nil }
        let ids = valid.isEmpty ? defaultFavoriteIds : valid
        defaults.set(ids, forKey: Key.favoriteTemplateIds)
        activePresetId = preset.id
        persistSharedState()
        NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
    }

    static func saveCurrentAsPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var customs = loadCustomPresets()
        let id = "custom.\(UUID().uuidString)"
        customs.append(FavoritePreset(id: id, name: trimmed, templateIds: favoriteTemplateIds, isBuiltIn: false))
        persistCustomPresets(customs)
        activePresetId = id
        NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
    }

    static func deletePreset(id: String) {
        var customs = loadCustomPresets()
        customs.removeAll { $0.id == id }
        persistCustomPresets(customs)
        if activePresetId == id {
            activePresetId = "custom"
        }
        NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
    }

    private static func loadCustomPresets() -> [FavoritePreset] {
        guard let data = defaults.data(forKey: Key.customPresets),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let ids = dict["templateIds"] as? [String]
            else { return nil }
            return FavoritePreset(id: id, name: name, templateIds: ids, isBuiltIn: false)
        }
    }

    private static func persistCustomPresets(_ presets: [FavoritePreset]) {
        let arr: [[String: Any]] = presets.map {
            ["id": $0.id, "name": $0.name, "templateIds": $0.templateIds]
        }
        if let data = try? JSONSerialization.data(withJSONObject: arr) {
            defaults.set(data, forKey: Key.customPresets)
        }
    }

    static func recordRecent(templateId: String) {
        guard FileTemplates.template(id: templateId) != nil else { return }
        var ids = recentTemplateIds.filter { $0 != templateId }
        ids.insert(templateId, at: 0)
        recentTemplateIds = Array(ids.prefix(maxRecent))
        NotificationCenter.default.post(name: .filePlusPreferencesChanged, object: nil)
    }

    static func persistSharedState() {
        AppSupport.syncSharedState(favorites: favoriteTemplateIds, recent: recentTemplateIds)
    }

    static func bootstrap() {
        AppSupport.ensureDirectories()
        if defaults.object(forKey: Key.favoriteTemplateIds) == nil {
            let shared = AppSupport.loadSharedState()
            if !shared.favorites.isEmpty {
                defaults.set(shared.favorites, forKey: Key.favoriteTemplateIds)
            }
            if defaults.object(forKey: Key.recentTemplateIds) == nil, !shared.recent.isEmpty {
                defaults.set(shared.recent, forKey: Key.recentTemplateIds)
            }
        }
        // Миграция старого значения "revealInFinder" остаётся валидной
        persistSharedState()
    }
}

extension Notification.Name {
    static let filePlusPreferencesChanged = Notification.Name("fileplus.preferencesChanged")
    static let filePlusActivateUI = Notification.Name("fileplus.activateUI")
}
