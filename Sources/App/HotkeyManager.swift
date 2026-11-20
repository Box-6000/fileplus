import AppKit
import Carbon.HIToolbox

/// Глобальный хоткей (Carbon RegisterEventHotKey), комбинация из настроек.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isRegistered = false
    private var registeredConfig: HotKeyConfig?

    private init() {}

    func start() {
        applyPreferences()
    }

    func stop() {
        unregister()
    }

    func applyPreferences() {
        if AppPreferences.hotkeyEnabled {
            let config = AppPreferences.hotKey
            if isRegistered, registeredConfig == config { return }
            unregister()
            register(config)
        } else {
            unregister()
        }
    }

    private func register(_ config: HotKeyConfig) {
        guard !isRegistered else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            filePlusHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(0x46504C53), id: 1) // 'FPLS'
        let regStatus = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if regStatus == noErr {
            isRegistered = true
            registeredConfig = config
        } else if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        isRegistered = false
        registeredConfig = nil
    }

    fileprivate func handleHotKey() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .filePlusActivateUI, object: nil)
            FileCreator.promptAndCreate(in: FileCreator.finderInsertionDirectory())
        }
    }
}

private func filePlusHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKey()
    return noErr
}
