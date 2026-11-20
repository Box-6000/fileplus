import Foundation

/// Общие пути Application Support для хоста и Finder Sync.
enum AppSupport {
    static let folderName = "FilePlus"

    static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    static var templatesURL: URL {
        rootURL.appendingPathComponent("Templates", isDirectory: true)
    }

    static var sharedStateURL: URL {
        rootURL.appendingPathComponent("favorites.json")
    }

    static func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: templatesURL, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: sharedStateURL.path) {
            syncSharedState(favorites: AppPreferences.defaultFavoriteIds, recent: [])
        }
    }

    static func syncSharedState(favorites: [String], recent: [String]) {
        ensureDirectoriesExistOnly()
        let payload: [String: Any] = [
            "favorites": favorites,
            "recent": recent,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: sharedStateURL, options: .atomic)
    }

    static func loadSharedState() -> (favorites: [String], recent: [String]) {
        guard let data = try? Data(contentsOf: sharedStateURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (AppPreferences.defaultFavoriteIds, [])
        }
        let favorites = (obj["favorites"] as? [String]) ?? AppPreferences.defaultFavoriteIds
        let recent = (obj["recent"] as? [String]) ?? []
        return (favorites, recent)
    }

    private static func ensureDirectoriesExistOnly() {
        try? FileManager.default.createDirectory(at: templatesURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
}
