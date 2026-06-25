import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onPressed: (() -> Void)?
    private var onReleased: (() -> Void)?
    private static weak var current: HotkeyManager?

    deinit {
        unregister()
    }

    func registerOptionSpace(onPressed: @escaping () -> Void, onReleased: @escaping () -> Void) {
        unregister()
        self.onPressed = onPressed
        self.onReleased = onReleased
        Self.current = self

        let eventSpecs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyReleased)
            )
        ]

        _ = eventSpecs.withUnsafeBufferPointer { specs in
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

                    let eventKind = GetEventKind(event)
                    DispatchQueue.main.async {
                        if eventKind == OSType(kEventHotKeyPressed) {
                            HotkeyManager.current?.onPressed?()
                        } else if eventKind == OSType(kEventHotKeyReleased) {
                            HotkeyManager.current?.onReleased?()
                        }
                    }

                    return noErr
                },
                specs.count,
                specs.baseAddress,
                nil,
                &eventHandlerRef
            )
        }

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
