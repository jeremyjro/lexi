import AppKit
import SwiftUI

final class RawCapturePanelController {
    var onDismiss: (() -> Void)?
    var onNestedLookupRequested: ((String, LookupNavigationStack) -> Void)? {
        didSet {
            panel.onNestedLookupRequested = onNestedLookupRequested
        }
    }

    private let panel: RawCapturePanel
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var mouseMonitor: Any?

    init() {
        panel = RawCapturePanel()
        installDismissalMonitors()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var selectedAnswerText: String? {
        let text = panel.selectedAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var currentAnswer: String? {
        panel.currentAnswer
    }

    var currentLookupStack: LookupNavigationStack? {
        panel.currentLookupStack
    }

    func show(status: RawCapturePanelStatus, anchorRect: CGRect?) {
        panel.update(status: status)
        panel.position(anchorRect: anchorRect)
        panel.orderFrontRegardless()
    }

    func update(status: RawCapturePanelStatus) {
        panel.update(status: status)
    }

    @discardableResult
    func requestNestedLookup(term: String) -> Bool {
        panel.requestNestedLookup(term: term)
    }

    func beginNestedLookup(term: String) -> UUID? {
        panel.beginNestedLookup(term: term)
    }

    func updateLookupAnswer(nodeId: UUID, answer: String) {
        panel.updateLookupAnswer(nodeId: nodeId, answer: answer)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        onDismiss?()
    }

    private func installDismissalMonitors() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard panel.isVisible else { return false }
        if event.keyCode == 123 {
            _ = panel.popLookup()
            return true
        }
        if event.keyCode == 124 {
            if !panel.requestNestedLookupFromSelection() {
                panel.jumpToLatestChildLookup()
            }
            return true
        }
        if event.keyCode == 53 {
            hide()
            return true
        }
        return false
    }
}

final class RawCapturePanel: NSPanel {
    private let viewModel = RawCapturePanelViewModel()
    private let panelSize = NSSize(width: 420, height: 380)

    var onNestedLookupRequested: ((String, LookupNavigationStack) -> Void)? {
        get { viewModel.onNestedLookupRequested }
        set { viewModel.onNestedLookupRequested = newValue }
    }

    override var canBecomeKey: Bool { true }
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

    var selectedAnswerText: String {
        let liveSelection = liveSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return liveSelection.isEmpty ? viewModel.selectedAnswerText : liveSelection
    }

    var currentAnswer: String? {
        viewModel.currentAnswer
    }

    var currentLookupStack: LookupNavigationStack? {
        viewModel.currentLookupStack
    }

    func update(status: RawCapturePanelStatus) {
        viewModel.update(status: status)
    }

    @discardableResult
    func requestNestedLookup(term: String) -> Bool {
        viewModel.requestNestedLookup(term: term)
    }

    @discardableResult
    func requestNestedLookupFromSelection() -> Bool {
        viewModel.requestNestedLookupFromSelection()
    }

    func beginNestedLookup(term: String) -> UUID? {
        viewModel.beginNestedLookup(term: term)
    }

    func updateLookupAnswer(nodeId: UUID, answer: String) {
        viewModel.updateLookupAnswer(nodeId: nodeId, answer: answer)
    }

    func popLookup() -> Bool {
        viewModel.popLookup()
    }

    func jumpToRootLookup() {
        viewModel.jumpToRootLookup()
    }

    @discardableResult
    func jumpToLatestChildLookup() -> Bool {
        viewModel.jumpToLatestChildLookup()
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

    private var liveSelectedText: String {
        if let responder = firstResponder as? NSTextView {
            return responder.selectedText
        }
        guard let contentView else { return "" }
        return firstSelectedText(in: contentView)
    }

    private func firstSelectedText(in view: NSView) -> String {
        if let textView = view as? NSTextView {
            let text = textView.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        for subview in view.subviews {
            let text = firstSelectedText(in: subview)
            if !text.isEmpty { return text }
        }
        return ""
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
    case lookup(LookupNavigationStack)
    case buddyMessage(title: String, message: String)
    case buddyLoading(BuddyCaptureContext)
    case buddyStreaming(BuddyCaptureContext, String)
    case buddyError(BuddyCaptureContext?, String)
    case buddyPermissionMissing([BuddyPermission])
    case error(CapturedSelection?, String)
    case noSelection(appName: String, windowTitle: String)
    case noPermission
}

@MainActor
final class RawCapturePanelViewModel: ObservableObject {
    @Published var status: RawCapturePanelStatus = .noSelection(appName: "", windowTitle: "")
    @Published var selectedAnswerText = ""
    var onNestedLookupRequested: ((String, LookupNavigationStack) -> Void)?

    var currentAnswer: String? {
        switch status {
        case .streaming(_, let answer), .answered(_, let answer), .buddyStreaming(_, let answer):
            return answer
        case .lookup(let stack):
            return stack.currentNode?.answer
        default:
            return nil
        }
    }

    var currentLookupStack: LookupNavigationStack? {
        guard case .lookup(let stack) = status else { return nil }
        return stack
    }

    func update(status: RawCapturePanelStatus) {
        selectedAnswerText = ""
        self.status = status
    }

    @discardableResult
    func requestNestedLookup(term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, case .lookup(let stack) = status else { return false }
        onNestedLookupRequested?(trimmed, stack)
        return true
    }

    @discardableResult
    func requestNestedLookupFromSelection() -> Bool {
        requestNestedLookup(term: selectedAnswerText)
    }

    func beginNestedLookup(term: String) -> UUID? {
        guard case .lookup(var stack) = status else { return nil }
        let nodeId = stack.pushPending(term: term)
        selectedAnswerText = ""
        status = .lookup(stack)
        return nodeId
    }

    func updateLookupAnswer(nodeId: UUID, answer: String) {
        guard case .lookup(var stack) = status else { return }
        stack.updateAnswer(nodeId: nodeId, answer: answer)
        status = .lookup(stack)
    }

    func popLookup() -> Bool {
        guard case .lookup(var stack) = status else { return false }
        guard stack.pop() else { return false }
        selectedAnswerText = ""
        status = .lookup(stack)
        return true
    }

    func jumpToRootLookup() {
        guard case .lookup(var stack) = status else { return }
        stack.jumpToRoot()
        selectedAnswerText = ""
        status = .lookup(stack)
    }

    @discardableResult
    func jumpToLatestChildLookup() -> Bool {
        guard case .lookup(var stack) = status else { return false }
        guard stack.jumpToLatestChild() else { return false }
        selectedAnswerText = ""
        status = .lookup(stack)
        return true
    }

    func jump(to nodeId: UUID) {
        guard case .lookup(var stack) = status else { return }
        stack.jump(to: nodeId)
        selectedAnswerText = ""
        status = .lookup(stack)
    }
}

struct RawCapturePanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: RawCapturePanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            header
            Divider()
            content
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text(footerText)
                Spacer()
                Text(footerShortcutText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 420, height: 380, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("Lexi")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(statusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12), in: Capsule())
            Spacer()
            Text("⌥ Space")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var header: some View {
        switch viewModel.status {
        case .captured(let capture), .loading(let capture), .streaming(let capture, _), .answered(let capture, _):
            captureHeader(capture)
        case .lookup(let stack):
            lookupHeader(stack)
        case .buddyMessage(let title, _):
            Text(title)
                .font(.headline)
        case .buddyLoading(let capture), .buddyStreaming(let capture, _):
            buddyHeader(capture)
        case .buddyError(let capture, _):
            if let capture {
                buddyHeader(capture)
            } else {
                Text("Buddy Capture needs attention")
                    .font(.headline)
            }
        case .buddyPermissionMissing:
            Text("Buddy Capture permissions needed")
                .font(.headline)
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
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Divider()
                    captureDetails(capture)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .lookup(let stack):
            lookupContent(stack)
        case .buddyMessage(_, let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("If no full-screen overlay appears, use Settings → Permissions to re-check Accessibility and Screen Recording for the installed /Applications/Lexi.app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .buddyLoading(let capture):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if reduceMotion {
                        Text("…")
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Asking about your screen…")
                        .font(.system(size: 14, weight: .medium))
                }
                buddyDetails(capture)
            }
        case .buddyStreaming(let capture, let answer):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(answer.isEmpty ? "…" : answer)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Divider()
                    buddyDetails(capture)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .buddyError(let capture, let message):
            VStack(alignment: .leading, spacing: 10) {
                Text("What happened")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                if let capture {
                    Divider()
                    buddyDetails(capture)
                }
            }
        case .buddyPermissionMissing(let permissions):
            VStack(alignment: .leading, spacing: 10) {
                Text("Open System Settings and enable these permissions for Lexi, then choose Re-check Permissions from the menu bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                ForEach(permissions, id: \.title) { permission in
                    Label(permission.title, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        case .error(let capture, let message):
            VStack(alignment: .leading, spacing: 10) {
                Text("What happened")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                Text("Highlight a word or phrase, hold Option + Space, then release.")
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

    private func lookupHeader(_ stack: LookupNavigationStack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            breadcrumb(stack)
            if let node = stack.currentNode {
                Text(node.term)
                    .font(.headline)
                    .lineLimit(2)
                Text("Depth \(stack.depth) · \(node.sourceLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lookupContent(_ stack: LookupNavigationStack) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let node = stack.currentNode {
                if node.answer.isEmpty {
                    HStack(spacing: 8) {
                        if reduceMotion {
                            Text("…")
                                .font(.system(size: 14, weight: .semibold))
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Explaining \"\(node.term)\"…")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    SelectableAnswerView(
                        text: node.answer,
                        onSelectionChanged: { viewModel.selectedAnswerText = $0 },
                        onDoubleClick: { _ in }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    metadataRow("Source", node.sourceLabel)
                    metadataRow("Window", node.windowTitle.isEmpty ? "Unknown" : node.windowTitle)
                    metadataRow("App", node.appName.isEmpty ? "Unknown" : node.appName)
                }
            }
        }
    }

    private func breadcrumb(_ stack: LookupNavigationStack) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(breadcrumbNodes(stack).enumerated()), id: \.offset) { _, item in
                switch item {
                case .node(let node):
                    Button(node.term) {
                        viewModel.jump(to: node.id)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(node.id == stack.currentId ? .bold : .regular))
                    .foregroundStyle(node.id == stack.currentId ? .primary : .secondary)
                    .lineLimit(1)
                case .ellipsis:
                    Text("…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item != breadcrumbNodes(stack).last {
                    Text("›")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private enum BreadcrumbItem: Equatable {
        case node(LookupNode)
        case ellipsis
    }

    private func breadcrumbNodes(_ stack: LookupNavigationStack) -> [BreadcrumbItem] {
        let path = stack.activePath
        guard path.count > 3 else { return path.map { .node($0) } }
        return [.node(path[0]), .ellipsis, .node(path[path.count - 2]), .node(path[path.count - 1])]
    }

    private var footerText: String {
        switch viewModel.status {
        case .answered:
            return "Answer ready · Copy Last Answer from menu"
        case .lookup(let stack):
            return stack.depth == 0 ? "Highlight inside answer, then press → to drill" : "← pops up · → drills down or reopens child"
        case .streaming, .buddyStreaming:
            return "Streaming from Railway…"
        case .buddyMessage:
            return "Drag a region or press Esc to cancel"
        case .loading, .buddyLoading:
            return "Waiting for first token…"
        case .buddyPermissionMissing:
            return "Grant Buddy Capture permissions"
        case .buddyError:
            return "Check Settings if this keeps happening"
        case .noSelection:
            return "Select text anywhere on your Mac"
        case .noPermission:
            return "Grant Accessibility for Lexi"
        case .error:
            return "Check Settings if this keeps happening"
        default:
            return "Ready"
        }
    }

    private var footerShortcutText: String {
        switch viewModel.status {
        case .lookup:
            return "← / → · Esc closes"
        default:
            return "Esc to dismiss"
        }
    }

    private var statusTitle: String {
        switch viewModel.status {
        case .captured:
            return "Captured"
        case .loading, .buddyLoading:
            return "Asking"
        case .buddyMessage:
            return "Buddy"
        case .streaming, .buddyStreaming:
            return "Streaming"
        case .answered:
            return "Answered"
        case .lookup(let stack):
            return stack.depth == 0 ? "Answered" : "Depth \(stack.depth)"
        case .buddyError, .buddyPermissionMissing, .error:
            return "Needs attention"
        case .noSelection:
            return "No selection"
        case .noPermission:
            return "Permission"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .answered, .lookup:
            return .green
        case .streaming, .loading, .buddyStreaming, .buddyLoading, .buddyMessage:
            return .blue
        case .error, .noPermission, .buddyError, .buddyPermissionMissing:
            return .orange
        case .noSelection:
            return .gray
        case .captured:
            return .purple
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

    private func buddyHeader(_ capture: BuddyCaptureContext) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(capture.displayTitle)
                .font(.headline)
                .lineLimit(2)
            Text("\(capture.appName) · Buddy Capture")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func buddyDetails(_ capture: BuddyCaptureContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let screenshot = capture.screenshot {
                HStack(alignment: .top, spacing: 10) {
                    Image(nsImage: screenshot.thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 92, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 6) {
                        metadataRow("Image", "\(screenshot.pixelWidth)×\(screenshot.pixelHeight)")
                        metadataRow("Source", "Buddy Capture")
                    }
                }
            } else {
                metadataRow("Image", "No screenshot captured")
            }

            if !capture.question.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Question")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(capture.question)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            metadataRow("Window", capture.windowTitle.isEmpty ? "Unknown" : capture.windowTitle)
            metadataRow("App", capture.appName)
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

private struct SelectableAnswerView: NSViewRepresentable {
    let text: String
    let onSelectionChanged: (String) -> Void
    let onDoubleClick: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = LexiSelectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.onDoubleClickSelection = onDoubleClick
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? LexiSelectableTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.delegate = context.coordinator
        textView.onDoubleClickSelection = onDoubleClick
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableAnswerView

        init(_ parent: SelectableAnswerView) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onSelectionChanged(textView.selectedText)
        }
    }
}

private final class LexiSelectableTextView: NSTextView {
    var onDoubleClickSelection: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount >= 2 else { return }
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onDoubleClickSelection?(text)
    }
}

private extension NSTextView {
    var selectedText: String {
        let range = selectedRange()
        guard range.length > 0, let swiftRange = Range(range, in: string) else { return "" }
        return String(string[swiftRange])
    }
}
