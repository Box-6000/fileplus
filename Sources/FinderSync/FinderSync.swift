import Cocoa
import FinderSync

/// Расширение Finder: пункты в обычном контекстном меню (не «Службы»),
/// включая клик по пустому месту на рабочем столе.
@objc(FinderSync)
class FinderSync: FIFinderSync {

    override init() {
        super.init()
        var urls = Set<URL>()
        let home = FileManager.default.homeDirectoryForCurrentUser
        urls.insert(home)
        urls.insert(home.appendingPathComponent("Desktop"))
        urls.insert(home.appendingPathComponent("Documents"))
        urls.insert(home.appendingPathComponent("Downloads"))
        urls.insert(URL(fileURLWithPath: "/"))
        if let volumes = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: nil
        ) {
            volumes.forEach { urls.insert($0) }
        }
        FIFinderSyncController.default().directoryURLs = urls
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer, .contextualMenuForSidebar:
            break
        default:
            return nil
        }

        let menu = NSMenu(title: "")
        let root = NSMenuItem(title: "Новый файл", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Новый файл")

        let choose = NSMenuItem(
            title: "Выбрать формат…",
            action: #selector(createWithDialog(_:)),
            keyEquivalent: ""
        )
        choose.target = self
        submenu.addItem(choose)
        submenu.addItem(NSMenuItem.separator())

        for item in SharedFavorites.loadMenuItems() {
            let mi = NSMenuItem(title: item.title, action: #selector(createTyped(_:)), keyEquivalent: "")
            mi.representedObject = item.id
            mi.target = self
            submenu.addItem(mi)
        }

        submenu.addItem(NSMenuItem.separator())
        let more = NSMenuItem(title: "Ещё форматы…", action: #selector(createWithDialog(_:)), keyEquivalent: "")
        more.target = self
        submenu.addItem(more)

        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    @objc func createWithDialog(_ sender: Any?) {
        guard let dir = targetDirectory() else { return }
        launchHost(arguments: ["--create", dir.path])
    }

    @objc func createTyped(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let dir = targetDirectory() else { return }
        launchHost(arguments: ["--quick", id, dir.path])
    }

    private func targetDirectory() -> URL? {
        let controller = FIFinderSyncController.default()
        if let targeted = controller.targetedURL() {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: targeted.path, isDirectory: &isDir), isDir.boolValue {
                return targeted
            }
            return targeted.deletingLastPathComponent()
        }
        if let selected = controller.selectedItemURLs()?.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: selected.path, isDirectory: &isDir), isDir.boolValue {
                return selected
            }
            return selected.deletingLastPathComponent()
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    private func launchHost(arguments: [String]) {
        let host = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments
        config.activates = true
        NSWorkspace.shared.openApplication(at: host, configuration: config) { _, error in
            if let error {
                NSLog("Файл+: не удалось запустить хост: %@", error.localizedDescription)
            }
        }
    }
}

/// Чтение избранного из Application Support (общий файл с хост-приложением).
private enum SharedFavorites {
    struct Item {
        let id: String
        let title: String
    }

    private static let fallback: [Item] = [
        Item(id: "txt", title: "Текст (.txt)"),
        Item(id: "md", title: "Markdown (.md)"),
        Item(id: "html", title: "HTML (.html)"),
        Item(id: "py", title: "Python (.py)"),
        Item(id: "js", title: "JavaScript (.js)"),
        Item(id: "json", title: "JSON (.json)"),
        Item(id: "swift", title: "Swift (.swift)"),
        Item(id: "docx", title: "Word (.docx)"),
    ]

    private static let titles: [String: String] = [
        "docx": "Word (.docx)",
        "xlsx": "Excel (.xlsx)",
        "pptx": "PowerPoint (.pptx)",
        "rtf": "Rich Text (.rtf)",
        "csv": "CSV (.csv)",
        "txt": "Текст (.txt)",
        "md": "Markdown (.md)",
        "json": "JSON (.json)",
        "xml": "XML (.xml)",
        "yml": "YAML (.yml)",
        "html": "HTML (.html)",
        "css": "CSS (.css)",
        "js": "JavaScript (.js)",
        "ts": "TypeScript (.ts)",
        "swift": "Swift (.swift)",
        "py": "Python (.py)",
        "go": "Go (.go)",
        "rs": "Rust (.rs)",
        "java": "Java (.java)",
        "sh": "Shell (.sh)",
        "sql": "SQL (.sql)",
        "env": ".env",
        "gitignore": ".gitignore",
        "dockerfile": "Dockerfile",
        "empty": "Без расширения",
    ]

    static func loadMenuItems() -> [Item] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let url = support.appendingPathComponent("FilePlus/favorites.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let favorites = obj["favorites"] as? [String],
              !favorites.isEmpty
        else {
            return fallback
        }

        return favorites.map { id in
            if id.hasPrefix("custom:") {
                let name = String(id.dropFirst("custom:".count))
                return Item(id: id, title: "\(name) (свой)")
            }
            return Item(id: id, title: titles[id] ?? id)
        }
    }
}
