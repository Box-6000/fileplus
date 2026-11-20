import AppKit
import ApplicationServices

/// Кнопка «＋» на экране + тихий перехват правого клика (без запросов разрешений).
final class DesktopClickMonitor {
    static let shared = DesktopClickMonitor()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var floatPanel: NSPanel?
    private var floatButton: NSButton?
    private var moveObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    func start() {
        if AppPreferences.interceptDesktopClick, AXIsProcessTrusted() {
            installTap()
        }
        installActivationObserver()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshFloatingButton()
        }
    }

    func stop() {
        tearDownTap()
        removeActivationObserver()
        hideFloatingButton()
    }

    private func installActivationObserver() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFloatingButtonWithFrontApp()
        }
    }

    private func removeActivationObserver() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    /// Кнопка только на «рабочем столе» (Finder) — не перекрывает окна других приложений.
    private func syncFloatingButtonWithFrontApp() {
        guard AppPreferences.showFloatingButton, floatPanel != nil else { return }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isDesktopContext = frontID == "com.apple.finder"
            || frontID == Bundle.main.bundleIdentifier
        if isDesktopContext {
            floatPanel?.orderFront(nil)
        } else {
            floatPanel?.orderOut(nil)
        }
    }

    func applyPreferences() {
        if AppPreferences.interceptDesktopClick, AXIsProcessTrusted() {
            if tap == nil { installTap() }
        } else {
            tearDownTap()
        }
        // Пересоздаём кнопку, чтобы применить прозрачность/фон
        if floatPanel != nil {
            hideFloatingButton()
        }
        refreshFloatingButton()
    }

    private func tearDownTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon {
                    let monitor = Unmanaged<DesktopClickMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                }
                return Unmanaged.passUnretained(event)
            }

            guard type == .rightMouseDown, let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<DesktopClickMonitor>.fromOpaque(refcon).takeUnretainedValue()
            guard AppPreferences.interceptDesktopClick else {
                return Unmanaged.passUnretained(event)
            }
            guard monitor.shouldInterceptDesktop(event) else {
                return Unmanaged.passUnretained(event)
            }
            let loc = event.location
            DispatchQueue.main.async { monitor.showMenu(at: loc) }
            return nil
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func shouldInterceptDesktop(_ event: CGEvent) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return false
        }
        return !isPointInsideFinderWindow(event.location)
    }

    private func isPointInsideFinderWindow(_ cgPoint: CGPoint) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for info in infoList {
            guard (info[kCGWindowOwnerName as String] as? String) == "Finder" else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let w = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let h = (bounds["Height"] as? NSNumber)?.doubleValue,
                  w >= 80, h >= 80
            else { continue }

            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer != 0 { continue }

            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rect.contains(cgPoint) { return true }
        }
        return false
    }

    private func cocoaPoint(from cgPoint: CGPoint) -> NSPoint {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            if bounds.contains(cgPoint) {
                let localX = cgPoint.x - bounds.origin.x
                let localY = cgPoint.y - bounds.origin.y
                return NSPoint(
                    x: screen.frame.minX + localX,
                    y: screen.frame.maxY - localY
                )
            }
        }
        let screenH = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return NSPoint(x: cgPoint.x, y: screenH - cgPoint.y)
    }

    private func showMenu(at cgLocation: CGPoint) {
        popCreateMenu(at: cocoaPoint(from: cgLocation), inDirectory: FileCreator.desktopDirectory())
    }

    private func popCreateMenu(at point: NSPoint, relativeTo view: NSView? = nil, inDirectory: URL) {
        let menu = buildCreateMenu(directory: inDirectory)
        if let view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
            return
        }
        let anchor = NSWindow(
            contentRect: NSRect(x: point.x, y: point.y, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.level = .popUpMenu
        anchor.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: .zero, in: anchor.contentView)
        anchor.orderOut(nil)
    }

    private func buildCreateMenu(directory: URL) -> NSMenu {
        let menu = NSMenu(title: "Файл+")
        let head = NSMenuItem(title: "Новый файл", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        let recent = AppPreferences.recentTemplates
        if !recent.isEmpty {
            for template in recent.prefix(5) {
                let item = NSMenuItem(title: template.displayName, action: #selector(createTyped(_:)), keyEquivalent: "")
                item.representedObject = CreateTarget(templateId: template.id, directory: directory)
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        for template in AppPreferences.favoriteTemplates {
            let item = NSMenuItem(title: template.displayName, action: #selector(createTyped(_:)), keyEquivalent: "")
            item.representedObject = CreateTarget(templateId: template.id, directory: directory)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let folder = NSMenuItem(title: "Новая папка…", action: #selector(createFolder(_:)), keyEquivalent: "")
        folder.representedObject = directory
        folder.target = self
        menu.addItem(folder)
        let more = NSMenuItem(title: "Все форматы…", action: #selector(createDialog(_:)), keyEquivalent: "")
        more.representedObject = directory
        more.target = self
        menu.addItem(more)
        return menu
    }

    func refreshFloatingButton() {
        if AppPreferences.showFloatingButton {
            if floatPanel == nil {
                showFloatingButton()
            } else {
                applyButtonAppearance()
            }
            syncFloatingButtonWithFrontApp()
        } else {
            hideFloatingButton()
        }
    }

    private func hideFloatingButton() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        floatPanel?.orderOut(nil)
        floatPanel = nil
        floatButton = nil
    }

    private func showFloatingButton() {
        guard floatPanel == nil, let screen = NSScreen.main else { return }
        let side: CGFloat = 56
        let margin: CGFloat = 24
        let defaultFrame = NSRect(
            x: screen.visibleFrame.maxX - side - margin,
            y: screen.visibleFrame.minY + margin,
            width: side,
            height: side
        )
        var frame = defaultFrame
        if let saved = AppPreferences.floatingOrigin {
            frame.origin = saved
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
            if !onScreen { frame = defaultFrame }
        }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .normal
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: side, height: side))
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = side / 2
        btn.target = self
        btn.action = #selector(floatingClicked(_:))
        btn.toolTip = "Файл+ — создать файл (перетащите, чтобы переместить)"

        panel.contentView = btn
        floatPanel = panel
        floatButton = btn
        applyButtonAppearance()
        syncFloatingButtonWithFrontApp()

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            AppPreferences.floatingOrigin = window.frame.origin
            self?.floatPanel = window as? NSPanel
        }
    }

    private func applyButtonAppearance() {
        guard let btn = floatButton else { return }
        let side = btn.bounds.width
        if AppPreferences.floatingButtonOpaque {
            btn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        } else {
            btn.layer?.backgroundColor = NSColor.clear.cgColor
        }
        btn.layer?.cornerRadius = side / 2

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        btn.attributedTitle = NSAttributedString(
            string: "＋",
            attributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: NSColor.white,
                .shadow: shadow,
            ]
        )
    }

    @objc private func floatingClicked(_ sender: NSButton) {
        let dir = FileCreator.finderInsertionDirectory()
        popCreateMenu(at: .zero, relativeTo: sender, inDirectory: dir)
    }

    @objc private func createDialog(_ sender: NSMenuItem) {
        let dir = (sender.representedObject as? URL) ?? FileCreator.desktopDirectory()
        FileCreator.promptAndCreate(in: dir)
    }

    @objc private func createFolder(_ sender: NSMenuItem) {
        let dir = (sender.representedObject as? URL) ?? FileCreator.desktopDirectory()
        FileCreator.promptAndCreateFolder(in: dir)
    }

    @objc private func createTyped(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? CreateTarget else { return }
        FileCreator.createQuick(templateId: target.templateId, in: target.directory)
    }
}

private final class CreateTarget: NSObject {
    let templateId: String
    let directory: URL
    init(templateId: String, directory: URL) {
        self.templateId = templateId
        self.directory = directory
    }
}
