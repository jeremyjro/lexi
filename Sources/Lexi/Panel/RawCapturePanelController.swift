import AppKit
import SwiftUI

final class RawCapturePanelController {
    var onDismiss: (() -> Void)?

    private let panel: RawCapturePanel
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    init() {
        panel = RawCapturePanel()
        installDismissalMonitors()
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show(status: RawCapturePanelStatus, anchorRect: CGRect?) {
        panel.update(status: status)
        panel.position(anchorRect: anchorRect)
        panel.orderFrontRegardless()
    }

    func update(status: RawCapturePanelStatus) {
        panel.update(status: status)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        onDismiss?()
    }

    private func installDismissalMonitors() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
            }
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }
}

final class RawCapturePanel: NSPanel {
    private let viewModel = RawCapturePanelViewModel()
    private let panelSize = NSSize(width: 380, height: 340)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        contentView = NSHostingView(rootView: RawCapturePanelView(viewModel: viewModel))
    }

    func update(status: RawCapturePanelStatus) {
        viewModel.status = status
    }

    func position(anchorRect: CGRect?) {
        let screen = screen(containing: anchorRect) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let anchor = anchorRect ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let gap: CGFloat = 10
        let inset: CGFloat = 8

        var origin: NSPoint
        if anchorRect == nil {
            origin = NSPoint(x: anchor.origin.x + 14, y: anchor.origin.y - panelSize.height - 14)
        } else {
            let belowY = anchor.minY - panelSize.height - gap
            let aboveY = anchor.maxY + gap
            let roomBelow = anchor.minY - visibleFrame.minY
            let roomAbove = visibleFrame.maxY - anchor.maxY
            origin = NSPoint(
                x: anchor.midX - panelSize.width / 2,
                y: roomBelow >= panelSize.height + gap || roomBelow >= roomAbove ? belowY : aboveY
            )
        }

        origin.x = min(max(origin.x, visibleFrame.minX + inset), visibleFrame.maxX - panelSize.width - inset)
        origin.y = min(max(origin.y, visibleFrame.minY + inset), visibleFrame.maxY - panelSize.height - inset)

        if let anchorRect {
            var frame = NSRect(origin: origin, size: panelSize)
            if frame.intersects(anchorRect) {
                let aboveY = min(anchorRect.maxY + gap, visibleFrame.maxY - panelSize.height - inset)
                let belowY = max(anchorRect.minY - panelSize.height - gap, visibleFrame.minY + inset)
                origin.y = visibleFrame.maxY - anchorRect.maxY > anchorRect.minY - visibleFrame.minY ? aboveY : belowY
                frame.origin = origin
            }
        }

        setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func screen(containing anchorRect: CGRect?) -> NSScreen? {
        guard let anchorRect else { return NSScreen.screens.first { $0.visibleFrame.contains(NSEvent.mouseLocation) } }
        return NSScreen.screens.first { $0.visibleFrame.intersects(anchorRect) }
    }
}

enum RawCapturePanelStatus {
    case captured(CapturedSelection)
    case loading(CapturedSelection)
    case streaming(CapturedSelection, String)
    case answered(CapturedSelection, String)
    case error(CapturedSelection?, String)
    case noSelection(appName: String, windowTitle: String)
    case noPermission
}

@MainActor
final class RawCapturePanelViewModel: ObservableObject {
    @Published var status: RawCapturePanelStatus = .noSelection(appName: "", windowTitle: "")
}

struct RawCapturePanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: RawCapturePanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 380, height: 340, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var header: some View {
        switch viewModel.status {
        case .captured(let capture), .loading(let capture), .streaming(let capture, _), .answered(let capture, _):
            captureHeader(capture)
        case .error(let capture, _):
            if let capture {
                captureHeader(capture)
            } else {
                Text("Couldn't reach the assistant")
                    .font(.headline)
            }
        case .noSelection:
            Text("Select some text first")
                .font(.headline)
        case .noPermission:
            Text("Accessibility permission needed")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.status {
        case .captured(let capture):
            captureDetails(capture)
        case .loading(let capture):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if reduceMotion {
                        Text("…")
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Asking Lexi…")
                        .font(.system(size: 14, weight: .medium))
                }
                captureDetails(capture)
            }
        case .streaming(let capture, let answer), .answered(let capture, let answer):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(answer.isEmpty ? "…" : answer)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                    Divider()
                    captureDetails(capture)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .error(let capture, let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                if let capture {
                    Divider()
                    captureDetails(capture)
                }
            }
        case .noSelection(let appName, let windowTitle):
            VStack(alignment: .leading, spacing: 8) {
                Text("Highlight a word or phrase, then press Option + Space or Option + Command.")
                metadataRow("App", appName.isEmpty ? "Unknown" : appName)
                metadataRow("Window", windowTitle.isEmpty ? "Unknown" : windowTitle)
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        case .noPermission:
            Text("Open Lexi from the menu bar and choose Re-check Accessibility Permission after enabling Lexi in System Settings → Privacy & Security → Accessibility.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var footerText: String {
        switch viewModel.status {
        case .answered:
            return "Esc, click away, or hotkey again to dismiss"
        case .streaming:
            return "Streaming…"
        case .loading:
            return "Waiting for first token…"
        default:
            return "Lexi"
        }
    }

    private func captureHeader(_ capture: CapturedSelection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(capture.term)
                .font(.headline)
                .lineLimit(2)
            Text("\(capture.appName)" + sourceSuffix(capture.source))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func captureDetails(_ capture: CapturedSelection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow("Window", capture.windowTitle.isEmpty ? "Unknown" : capture.windowTitle)
            metadataRow("App", capture.appName)
            metadataRow("Source", capture.source == .accessibility ? "Accessibility API" : "Clipboard fallback")

            VStack(alignment: .leading, spacing: 4) {
                Text("Passage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(capture.passage.isEmpty ? "No surrounding context captured." : capture.passage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func sourceSuffix(_ source: CapturedSelection.Source) -> String {
        source == .accessibility ? " · AX" : " · Clipboard fallback"
    }
}
