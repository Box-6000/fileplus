import AppKit

@main
struct FilePlusApp {
    static func main() {
        let args = CommandLine.arguments
        let bundleId = Bundle.main.bundleIdentifier ?? "com.konstantindzon.fileplus"

        // Один экземпляр в меню, кроме CLI-вызовов из Finder Sync
        let isCLI = args.contains("--create") || args.contains("--quick")
        if !isCLI {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                existing.activate(options: [.activateIgnoringOtherApps])
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name("com.konstantindzon.fileplus.activate"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                exit(0)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.konstantindzon.fileplus.activate"),
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .filePlusActivateUI, object: nil)
        }

        app.run()
    }
}
