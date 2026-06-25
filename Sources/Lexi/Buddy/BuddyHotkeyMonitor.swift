import AppKit
import CoreGraphics

final class BuddyHotkeyMonitor {
    var onBegin: (@MainActor (CGPoint) -> Void)?
    var onEnd: (@MainActor (CGPoint) -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var onInstallFailed: (@MainActor () -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isActive = false
    private var isDragging = false
    private var wasOptionCommandHeld = false
    private var isOptionCommandArmed = false

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil, globalFlagsMonitor == nil, localFlagsMonitor == nil else { return }
        installFallbackFlagMonitors()

        let mask = Self.mask([
            .flagsChanged,
            .keyDown,
        ])

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<BuddyHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            dispatch { self.onInstallFailed?() }
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            dispatch { self.onInstallFailed?() }
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        isActive = false
        isDragging = false
        wasOptionCommandHeld = false
        isOptionCommandArmed = false
    }

    func cancelActiveCapture() {
        guard isActive else { return }
        isActive = false
        isDragging = false
        isOptionCommandArmed = false
        dispatch { self.onCancel?() }
    }

    func completeActiveCapture() {
        isActive = false
        isDragging = false
        isOptionCommandArmed = false
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            if isActive, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                cancelActiveCapture()
                return nil
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func installFallbackFlagMonitors() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        handleOptionCommandState(event.flags.contains(.maskAlternate) && event.flags.contains(.maskCommand))
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        handleOptionCommandState(flags.contains(.option) && flags.contains(.command))
    }

    private func handleOptionCommandState(_ optionCommandHeld: Bool) {
        if optionCommandHeld && !wasOptionCommandHeld && !isActive {
            isActive = true
            isDragging = false
            isOptionCommandArmed = false
            let location = mouseLocation()
            dispatch { self.onBegin?(location) }
        } else if !optionCommandHeld && wasOptionCommandHeld && isActive {
            isActive = false
            isDragging = false
            isOptionCommandArmed = false
            let location = mouseLocation()
            dispatch { self.onEnd?(location) }
        }
        wasOptionCommandHeld = optionCommandHeld
    }

    private func mouseLocation() -> CGPoint {
        NSEvent.mouseLocation
    }

    private func dispatch(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            work()
        }
    }

    private static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }
}
