import AppKit
import ApplicationServices

enum FileCreator {
    static func targetDirectory(from urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue { return first }
        return first.deletingLastPathComponent()
    }

    static func finderInsertionDirectory() -> URL {
        let source = """
        tell application "Finder"
            try
                set sel to selection as alias list
                if (count of sel) > 0 then
                    set s to item 1 of sel
                    try
                        if class of s is folder then
                            return POSIX path of s
                        end if
                    end try
                    return POSIX path of (container of s as alias)
                end if
            end try
            try
                return POSIX path of (insertion location as alias)
            end try
            try
                if (count of Finder windows) > 0 then
                    return POSIX path of (target of front window as alias)
                end if
            end try
            return POSIX path of (path to desktop folder)
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            if error == nil, let path = result.stringValue, !path.isEmpty {
                var url = URL(fileURLWithPath: path)
                if url.path.hasSuffix("/") {
                    url = URL(fileURLWithPath: String(url.path.dropLast()))
                }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    return isDir.boolValue ? url : url.deletingLastPathComponent()
                }
                return url
            }
        }
        return desktopDirectory()
    }

    static func desktopDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static func sanitizeFileName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "/", with: "-")
        name = name.replacingOccurrences(of: ":", with: "-")
        name = name.replacingOccurrences(of: "\0", with: "")
        if name == "." || name == ".." || name.isEmpty {
            return "Новый файл"
        }
        return name
    }

    static func uniqueURL(in directory: URL, preferredName: String) -> URL {
        let safeName = sanitizeFileName(preferredName)
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(safeName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let ns = safeName as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
            if index > 10_000 { return candidate }
        }
    }

    private static func data(for template: FileTemplate, fileName: String) throws -> Data {
        switch template.payload {
        case .text(let string):
            let resolved = FileTemplates.applyVariables(string, fileName: fileName)
            return resolved.data(using: .utf8) ?? Data()
        case .resource(let name):
            let candidates = [
                Bundle.main.resourceURL?
                    .appendingPathComponent("templates", isDirectory: true)
                    .appendingPathComponent(name),
                Bundle.main.bundleURL
                    .appendingPathComponent("Contents/Resources/templates/\(name)"),
            ].compactMap { $0 }
            for url in candidates {
                if let data = try? Data(contentsOf: url) { return data }
            }
            throw NSError(
                domain: "FilePlus",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Шаблон не найден: \(name)"]
            )
        case .file(let url):
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8), !text.contains("\0") {
                let resolved = FileTemplates.applyVariables(text, fileName: fileName)
                return resolved.data(using: .utf8) ?? data
            }
            return data
        }
    }

    /// Показать в Finder и по возможности сразу войти в режим переименования.
    static func revealAndBeginRename(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        // Return в Finder = переименовать выбранный элемент (нужен Универсальный доступ)
        guard AXIsProcessTrusted() else { return }
        let escaped = url.path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Finder"
            activate
            set theItem to (POSIX file "\(escaped)") as alias
            select theItem
            delay 0.2
        end tell
        tell application "System Events"
            tell process "Finder"
                keystroke return
            end tell
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
        }
    }

    static func applyPostCreateAction(to url: URL) {
        switch AppPreferences.postCreateAction {
        case .revealAndRename:
            revealAndBeginRename(url: url)
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openInApp:
            NSWorkspace.shared.open(url)
        case .nothing:
            break
        }
    }

    @discardableResult
    static func createFile(
        in directory: URL,
        name: String,
        template: FileTemplate,
        applyPostAction: Bool = true
    ) throws -> URL {
        var lastError: Error?
        for _ in 0..<8 {
            let url = uniqueURL(in: directory, preferredName: name)
            do {
                let payload = try data(for: template, fileName: url.lastPathComponent)
                try payload.write(to: url, options: .withoutOverwriting)
                if name.hasSuffix(".sh") || name.hasSuffix(".py") || url.pathExtension == "sh" || url.pathExtension == "py" {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
                AppPreferences.recordRecent(templateId: template.id)
                if applyPostAction {
                    applyPostCreateAction(to: url)
                }
                return url
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                lastError = error
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? NSError(
            domain: "FilePlus",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Не удалось подобрать уникальное имя файла"]
        )
    }

    @discardableResult
    static func createFolder(in directory: URL, name: String, applyPostAction: Bool = true) throws -> URL {
        let safe = sanitizeFileName(name.isEmpty ? "Новая папка" : name)
        var lastError: Error?
        for _ in 0..<8 {
            let url = uniqueURL(in: directory, preferredName: safe)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                if applyPostAction {
                    applyPostCreateAction(to: url)
                }
                return url
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                lastError = error
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? NSError(
            domain: "FilePlus",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Не удалось создать папку"]
        )
    }

    static func createQuick(templateId: String, in directory: URL) {
        guard let template = FileTemplates.template(id: templateId) else {
            let alert = NSAlert()
            alert.messageText = "Неизвестный формат"
            alert.informativeText = "Шаблон «\(templateId)» не найден."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        do {
            _ = try createFile(in: directory, name: template.defaultFileName(), template: template)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Не удалось создать файл"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    static func createQuickFolder(in directory: URL) {
        do {
            _ = try createFolder(in: directory, name: "Новая папка")
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Не удалось создать папку"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    static func promptAndCreateFolder(in directory: URL) {
        let alert = NSAlert()
        alert.messageText = "Создать папку"
        alert.informativeText = "Папка: \(directory.path)"
        alert.addButton(withTitle: "Создать")
        alert.addButton(withTitle: "Отмена")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        nameField.stringValue = "Новая папка"
        alert.accessoryView = nameField

        DispatchQueue.main.async {
            nameField.selectText(nil)
            alert.window.makeFirstResponder(nameField)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = sanitizeFileName(nameField.stringValue.isEmpty ? "Новая папка" : nameField.stringValue)
        do {
            _ = try createFolder(in: directory, name: name)
        } catch {
            let err = NSAlert(error: error)
            err.messageText = "Не удалось создать папку"
            err.runModal()
        }
    }

    static func promptAndCreate(in directory: URL) {
        let alert = NSAlert()
        alert.messageText = "Создать новый файл"
        alert.informativeText = "Папка: \(directory.path)"
        alert.addButton(withTitle: "Создать")
        alert.addButton(withTitle: "Отмена")

        let width: CGFloat = 420
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 78))

        let templates = FileTemplates.all
        let typeLabel = NSTextField(labelWithString: "Формат:")
        typeLabel.frame = NSRect(x: 0, y: 48, width: 60, height: 22)
        let typePopup = NSPopUpButton(frame: NSRect(x: 66, y: 44, width: width - 66, height: 26))
        for template in templates {
            typePopup.addItem(withTitle: template.displayName)
        }

        let nameLabel = NSTextField(labelWithString: "Имя:")
        nameLabel.frame = NSRect(x: 0, y: 10, width: 60, height: 22)
        let nameField = NSTextField(frame: NSRect(x: 66, y: 8, width: width - 66, height: 24))
        if let first = templates.first {
            nameField.stringValue = first.defaultFileName()
        }

        if let recent = AppPreferences.recentTemplateIds.first,
           let idx = templates.firstIndex(where: { $0.id == recent }) {
            typePopup.selectItem(at: idx)
            nameField.stringValue = templates[idx].defaultFileName()
        }

        typePopup.target = NameFieldUpdater.shared
        typePopup.action = #selector(NameFieldUpdater.popupChanged(_:))
        NameFieldUpdater.shared.nameField = nameField
        NameFieldUpdater.shared.templates = templates

        container.addSubview(typeLabel)
        container.addSubview(typePopup)
        container.addSubview(nameLabel)
        container.addSubview(nameField)
        alert.accessoryView = container

        DispatchQueue.main.async {
            nameField.selectText(nil)
            alert.window.makeFirstResponder(nameField)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let index = max(0, typePopup.indexOfSelectedItem)
        guard index < templates.count else { return }
        let template = templates[index]
        var fileName: String
        if nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fileName = template.defaultFileName()
        } else {
            fileName = sanitizeFileName(nameField.stringValue)
        }

        switch template.id {
        case "dockerfile":
            if (fileName as NSString).pathExtension.isEmpty && !fileName.lowercased().contains("dockerfile") {
                fileName = "Dockerfile"
            }
        case "gitignore":
            if !fileName.hasPrefix(".") { fileName = ".gitignore" }
        case "env":
            if fileName != ".env" && (fileName as NSString).pathExtension.isEmpty {
                fileName = ".env"
            }
        default:
            let ns = fileName as NSString
            if !template.ext.isEmpty && ns.pathExtension.isEmpty {
                fileName = "\(fileName).\(template.ext)"
            }
        }

        fileName = sanitizeFileName(fileName)

        do {
            _ = try createFile(in: directory, name: fileName, template: template)
        } catch {
            let err = NSAlert(error: error)
            err.messageText = "Не удалось создать файл"
            err.runModal()
        }
    }
}

private final class NameFieldUpdater: NSObject {
    static let shared = NameFieldUpdater()
    weak var nameField: NSTextField?
    var templates: [FileTemplate] = []

    @objc func popupChanged(_ sender: NSPopUpButton) {
        let index = max(0, sender.indexOfSelectedItem)
        guard index < templates.count else { return }
        nameField?.stringValue = templates[index].defaultFileName()
    }
}
