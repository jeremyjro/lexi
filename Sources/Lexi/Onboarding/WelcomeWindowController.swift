import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private var didInvokeFinish = false
    private var onFinish: (() -> Void)?

    convenience init(onFinish: @escaping @MainActor () -> Void) {
        let hostingController = NSHostingController(
            rootView: WelcomeFlowView(
                onFinish: {},
                onSkip: nil
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Lexi"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 720, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(
            calibratedRed: 0.99,
            green: 0.95,
            blue: 0.91,
            alpha: 1.0
        )
        self.init(window: window)
        self.window?.delegate = self
        self.onFinish = { onFinish() }

        hostingController.rootView = WelcomeFlowView(
            onFinish: { [weak self] in
                self?.completeAndClose()
            },
            onSkip: nil
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard !didInvokeFinish else { return }
        didInvokeFinish = true
        onFinish?()
    }

    private func completeAndClose() {
        guard !didInvokeFinish else { return }
        didInvokeFinish = true
        onFinish?()
        window?.close()
    }
}
