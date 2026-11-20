import Foundation

enum TemplatePayload {
    case text(String)
    case resource(String) // filename in Resources/templates/
    case file(URL) // custom template on disk
}

struct FileTemplate: Identifiable, Equatable {
    let id: String
    let title: String
    let ext: String
    let payload: TemplatePayload
    let isCustom: Bool

    init(id: String, title: String, ext: String, payload: TemplatePayload, isCustom: Bool = false) {
        self.id = id
        self.title = title
        self.ext = ext
        self.payload = payload
        self.isCustom = isCustom
    }

    var displayName: String {
        if isCustom {
            return ext.isEmpty ? "\(title) (свой)" : "\(title) (.\(ext), свой)"
        }
        switch id {
        case "dockerfile": return "Dockerfile"
        case "gitignore": return ".gitignore"
        case "env": return ".env"
        case "empty": return "Без расширения"
        default:
            return ext.isEmpty ? title : "\(title) (.\(ext))"
        }
    }

    func defaultFileName() -> String {
        switch id {
        case "dockerfile": return "Dockerfile"
        case "gitignore": return ".gitignore"
        case "env": return ".env"
        default:
            if ext.isEmpty { return "Новый файл" }
            return "Новый файл.\(ext)"
        }
    }

    static func == (lhs: FileTemplate, rhs: FileTemplate) -> Bool {
        lhs.id == rhs.id
    }
}

enum FileTemplates {
    private static let builtIn: [FileTemplate] = [
        FileTemplate(id: "docx", title: "Word", ext: "docx", payload: .resource("empty.docx")),
        FileTemplate(id: "xlsx", title: "Excel", ext: "xlsx", payload: .resource("empty.xlsx")),
        FileTemplate(id: "pptx", title: "PowerPoint", ext: "pptx", payload: .resource("empty.pptx")),
        FileTemplate(id: "rtf", title: "Rich Text", ext: "rtf", payload: .text("{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24\n}")),
        FileTemplate(id: "csv", title: "CSV", ext: "csv", payload: .text("")),
        FileTemplate(id: "txt", title: "Текст", ext: "txt", payload: .text("")),
        FileTemplate(id: "md", title: "Markdown", ext: "md", payload: .text("# {{name}}\n\n")),
        FileTemplate(id: "json", title: "JSON", ext: "json", payload: .text("{\n  \n}\n")),
        FileTemplate(id: "xml", title: "XML", ext: "xml", payload: .text("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n  \n</root>\n")),
        FileTemplate(id: "yml", title: "YAML", ext: "yml", payload: .text("")),
        FileTemplate(id: "html", title: "HTML", ext: "html", payload: .text("<!DOCTYPE html>\n<html lang=\"ru\">\n<head>\n  <meta charset=\"UTF-8\" />\n  <title>{{name}}</title>\n</head>\n<body>\n\n</body>\n</html>\n")),
        FileTemplate(id: "css", title: "CSS", ext: "css", payload: .text("")),
        FileTemplate(id: "js", title: "JavaScript", ext: "js", payload: .text("")),
        FileTemplate(id: "ts", title: "TypeScript", ext: "ts", payload: .text("")),
        FileTemplate(id: "swift", title: "Swift", ext: "swift", payload: .text("import Foundation\n\n")),
        FileTemplate(id: "py", title: "Python", ext: "py", payload: .text("#!/usr/bin/env python3\n\n")),
        FileTemplate(id: "go", title: "Go", ext: "go", payload: .text("package main\n\nfunc main() {\n\t\n}\n")),
        FileTemplate(id: "rs", title: "Rust", ext: "rs", payload: .text("fn main() {\n    \n}\n")),
        FileTemplate(id: "java", title: "Java", ext: "java", payload: .text("public class Main {\n    public static void main(String[] args) {\n        \n    }\n}\n")),
        FileTemplate(id: "sh", title: "Shell", ext: "sh", payload: .text("#!/bin/zsh\n\n")),
        FileTemplate(id: "sql", title: "SQL", ext: "sql", payload: .text("")),
        FileTemplate(id: "env", title: "Env", ext: "env", payload: .text("")),
        FileTemplate(id: "gitignore", title: "gitignore", ext: "", payload: .text("")),
        FileTemplate(id: "dockerfile", title: "Dockerfile", ext: "", payload: .text("FROM alpine:latest\n\n")),
        FileTemplate(id: "empty", title: "Без расширения", ext: "", payload: .text("")),
    ]

    static var all: [FileTemplate] {
        builtIn + loadCustomTemplates()
    }

    static func template(id: String) -> FileTemplate? {
        all.first { $0.id == id }
    }

    static func loadCustomTemplates() -> [FileTemplate] {
        AppSupport.ensureDirectories()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: AppSupport.templatesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files.compactMap { url -> FileTemplate? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
            let name = url.lastPathComponent
            let ns = name as NSString
            let ext = ns.pathExtension
            let title = ext.isEmpty ? name : ns.deletingPathExtension
            let id = "custom:\(name)"
            return FileTemplate(
                id: id,
                title: title,
                ext: ext,
                payload: .file(url),
                isCustom: true
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Подстановка переменных в текстовых шаблонах.
    static func applyVariables(_ text: String, fileName: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: Date())
        let baseName = (fileName as NSString).deletingPathExtension
        let name = baseName.isEmpty ? fileName : baseName
        return text
            .replacingOccurrences(of: "{{date}}", with: date)
            .replacingOccurrences(of: "{{time}}", with: time)
            .replacingOccurrences(of: "{{name}}", with: name)
    }
}
