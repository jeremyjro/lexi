import AppKit
import CoreGraphics

final class BuddyPushToTalkMonitor {
    var onPressed: (@MainActor () -> Void)?
    var onReleased: (@MainActor () -> Void)?
    var onInstallFailed: (@MainActor () -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }
        let mask = Self.mask([.flagsChanged, .keyDown, .keyUp])
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<BuddyPushToTalkMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
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
        isPressed = false
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged || type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let pressedNow = flags.contains(.maskControl) && flags.contains(.maskAlternate)
        if pressedNow && !isPressed {
            isPressed = true
            dispatch { self.onPressed?() }
        } else if !pressedNow && isPressed {
            isPressed = false
            dispatch { self.onReleased?() }
        }
        return Unmanaged.passUnretained(event)
    }

    private func dispatch(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in work() }
    }

    private static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }
}
