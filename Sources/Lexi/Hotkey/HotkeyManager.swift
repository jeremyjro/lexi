import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onHotkey: (() -> Void)?
    private static weak var current: HotkeyManager?

    deinit {
        unregister()
    }

    func registerOptionSpace(onHotkey: @escaping () -> Void) {
        unregister()
        self.onHotkey = onHotkey
        Self.current = self

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyReleased)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    HotkeyManager.current?.onHotkey?()
                }

                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(fourCharCode("Lexi")), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { result, character in
            (result << 8) + FourCharCode(character)
        }
    }
}
