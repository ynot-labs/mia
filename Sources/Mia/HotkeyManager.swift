import Carbon
import AppKit

/// Manages a global hotkey that works even when the app is in the background.
/// Uses Carbon's RegisterEventHotKey for system-wide keyboard shortcut registration.
final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isRegistered = false

    /// Register a global hotkey (Cmd+Shift+T by default for toggle translation).
    func register(
        key: UInt32 = UInt32(kVK_ANSI_T),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    ) {
        // Unregister existing hotkey first
        unregister()

        let hotkeyID = EventHotKeyID(signature: 0x6D_6961_00, id: 1) // 'mia\0'

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        // Install event handler
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return -1 }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleTrigger()
                return noErr
            },
            1, &eventType,
            selfPtr,
            &handlerRef
        )

        // Register the hotkey
        let status = RegisterEventHotKey(
            key,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr {
            isRegistered = true
        }
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        isRegistered = false
    }

    deinit {
        unregister()
    }

    var onAction: (() -> Void)?

    private func handleTrigger() {
        onAction?()
    }
}
