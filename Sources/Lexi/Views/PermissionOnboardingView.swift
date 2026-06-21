import AppKit
import SwiftUI

final class PermissionOnboardingWindowController: NSWindowController {
    init() {
        let hostingView = NSHostingView(rootView: PermissionOnboardingView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lexi Accessibility Permission"
        window.center()
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PermissionOnboardingView: View {
    @State private var isTrusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "textformat")
                    .font(.system(size: 34, weight: .semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Lexi")
                        .font(.title2.weight(.semibold))
                    Text("Lexi needs Accessibility access to read selected text in other apps.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Highlight confusing text anywhere on your Mac", systemImage: "text.cursor")
                Label("Press the global hotkey", systemImage: "keyboard")
                Label("See a context-aware explanation without switching apps", systemImage: "bubble.left.and.text.bubble.right")
            }
            .font(.body)

            Spacer()

            if isTrusted {
                Label("Accessibility permission is enabled.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Click the button below, then enable Lexi in System Settings → Privacy & Security → Accessibility.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Open Accessibility Settings") {
                    requestAccessibilityPrompt()
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Re-check") {
                    isTrusted = AXIsProcessTrusted()
                }

                Spacer()
            }
        }
        .padding(28)
        .frame(width: 500, height: 360)
    }

    private func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
