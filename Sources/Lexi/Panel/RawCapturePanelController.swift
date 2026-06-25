import AppKit
import SwiftUI

final class RawCapturePanelController {
    var onDismiss: (() -> Void)?
    var onNestedLookupRequested: ((String, LookupNavigationStack) -> Void)? {
        didSet {
            panel.onNestedLookupRequested = onNestedLookupRequested
        }
    }
    var onFollowUpRequested: ((String, LookupNavigationStack) -> Void)? {
        didSet {
            panel.onFollowUpRequested = onFollowUpRequested
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
        panel.update(status: status, resetExpansion: true)
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

    func beginFollowUp(question: String) -> UUID? {
        panel.beginFollowUp(question: question)
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
    private let expandedPanelSize = NSSize(width: 448, height: 560)
    private let collapsedPanelSize = NSSize(width: 244, height: 54)
    private let panelInset: CGFloat = 18

    var onNestedLookupRequested: ((String, LookupNavigationStack) -> Void)? {
        get { viewModel.onNestedLookupRequested }
        set { viewModel.onNestedLookupRequested = newValue }
    }
    var onFollowUpRequested: ((String, LookupNavigationStack) -> Void)? {
        get { viewModel.onFollowUpRequested }
        set { viewModel.onFollowUpRequested = newValue }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: expandedPanelSize),
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

        contentView = NSHostingView(rootView: RawCapturePanelView(viewModel: viewModel) { [weak self] animated in
            DispatchQueue.main.async {
                self?.applyTopRightFrame(animated: animated)
            }
        })
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

    func update(status: RawCapturePanelStatus, resetExpansion: Bool = false) {
        let wasExpanded = viewModel.isPanelExpanded
        viewModel.update(status: status, resetExpansion: resetExpansion)
        if isVisible, wasExpanded != viewModel.isPanelExpanded {
            applyTopRightFrame(animated: true)
        }
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

    func beginFollowUp(question: String) -> UUID? {
        viewModel.beginFollowUp(question: question)
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
        applyTopRightFrame(animated: false)
    }

    private var currentPanelSize: NSSize {
        viewModel.isPanelExpanded ? expandedPanelSize : collapsedPanelSize
    }

    private func applyTopRightFrame(animated: Bool) {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let size = currentPanelSize
        let origin = NSPoint(
            x: max(visibleFrame.minX + panelInset, visibleFrame.maxX - size.width - panelInset),
            y: max(visibleFrame.minY + panelInset, visibleFrame.maxY - size.height - panelInset)
        )
        setFrame(NSRect(origin: origin, size: size), display: true, animate: animated)
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

private extension RawCapturePanelStatus {
    var canCollapseToPill: Bool {
        switch self {
        case .loading, .streaming, .answered, .lookup, .buddyLoading, .buddyStreaming:
            return true
        default:
            return false
        }
    }

    var shouldAutoExpandOnEntry: Bool {
        switch self {
        case .answered:
            return true
        case .lookup(let stack):
            return stack.currentNode?.answer.isEmpty == false
        default:
            return false
        }
    }
}

@MainActor
final class RawCapturePanelViewModel: ObservableObject {
    @Published var status: RawCapturePanelStatus = .noSelection(appName: "", windowTitle: "")
    @Published var selectedAnswerText = ""
    @Published var followUpQuestion = ""
    @Published var isExpanded = true
    var onNestedLookupRequested: ((String, LookupNavigationStack) -> Void)?
    var onFollowUpRequested: ((String, LookupNavigationStack) -> Void)?

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

    var isPanelExpanded: Bool {
        !status.canCollapseToPill || isExpanded
    }

    func update(status: RawCapturePanelStatus, resetExpansion: Bool = false) {
        selectedAnswerText = ""
        followUpQuestion = ""
        if resetExpansion {
            isExpanded = !status.canCollapseToPill
        } else if status.shouldAutoExpandOnEntry || !status.canCollapseToPill {
            isExpanded = true
        }
        self.status = status
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = status.canCollapseToPill ? expanded : true
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

    @discardableResult
    func requestFollowUp() -> Bool {
        let trimmed = followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              case .lookup(let stack) = status,
              stack.currentNode?.answer.isEmpty == false else { return false }
        onFollowUpRequested?(trimmed, stack)
        followUpQuestion = ""
        return true
    }

    func beginNestedLookup(term: String) -> UUID? {
        guard case .lookup(var stack) = status else { return nil }
        let nodeId = stack.pushPending(term: term)
        selectedAnswerText = ""
        followUpQuestion = ""
        status = .lookup(stack)
        return nodeId
    }

    func beginFollowUp(question: String) -> UUID? {
        guard case .lookup(var stack) = status else { return nil }
        let nodeId = stack.pushFollowUp(question: question)
        selectedAnswerText = ""
        followUpQuestion = ""
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
    @State private var collapseTask: Task<Void, Never>?
    let onExpansionChanged: (Bool) -> Void

    var body: some View {
        Group {
            if viewModel.isPanelExpanded {
                expandedPanel
                    .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
            } else {
                collapsedPill
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: viewModel.isPanelExpanded ? 28 : 27, style: .continuous))
        .onHover { hovering in
            handleHover(hovering)
        }
        .onChange(of: viewModel.isPanelExpanded) { _, _ in
            onExpansionChanged(!reduceMotion)
        }
        .onDisappear {
            collapseTask?.cancel()
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: viewModel.isPanelExpanded)
    }

    private func handleHover(_ hovering: Bool) {
        collapseTask?.cancel()
        guard viewModel.status.canCollapseToPill else { return }
        let animation: Animation? = reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)
        if hovering {
            guard !viewModel.isPanelExpanded else { return }
            withAnimation(animation) {
                viewModel.setExpanded(true)
            }
        } else {
            guard viewModel.isPanelExpanded else { return }
            collapseTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(animation) {
                    viewModel.setExpanded(false)
                }
            }
        }
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            topBar
            header
            softDivider
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text(footerText)
                Spacer()
                Text(footerShortcutText)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 448, height: 560, alignment: .topLeading)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.48), Color.white.opacity(0.12), Color.black.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.20), radius: 28, x: 0, y: 18)
        .shadow(color: .white.opacity(0.20), radius: 1, x: 0, y: 1)
    }

    private var collapsedPill: some View {
        HStack(spacing: 10) {
            pillActivityIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(collapsedPillTitle)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Hover to expand")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 244, height: 54, alignment: .center)
        .background(collapsedPillBackground)
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.52), Color.white.opacity(0.14), Color.black.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
        .shadow(color: .white.opacity(0.20), radius: 1, x: 0, y: 1)
    }

    @ViewBuilder
    private var pillActivityIndicator: some View {
        switch viewModel.status {
        case .lookup, .answered:
            Circle()
                .fill(Color.green.opacity(0.82))
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))
        default:
            if reduceMotion {
                Circle()
                    .fill(Color.blue.opacity(0.78))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.72)
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var collapsedPillTitle: String {
        switch viewModel.status {
        case .loading:
            return "Generating answer"
        case .streaming:
            return "Streaming answer"
        case .buddyLoading:
            return "Reading screen"
        case .buddyStreaming:
            return "Streaming insight"
        case .answered, .lookup:
            return "Answer ready"
        default:
            return "Lexi"
        }
    }

    private var collapsedPillBackground: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.32), Color.white.opacity(0.10), Color.black.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(Capsule(style: .continuous))
            )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.26), Color.white.opacity(0.08), Color.black.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
    }

    private var softDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, Color.primary.opacity(0.12), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("Lexi")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(statusTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.7))
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
        case .streaming(_, let answer), .answered(_, let answer):
            ScrollView {
                answerBubble(answer.isEmpty ? "…" : answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .buddyStreaming(_, let answer):
            ScrollView {
                answerBubble(answer.isEmpty ? "…" : answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("Hold Option + Space while selecting a word or phrase, then release.")
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

    private func answerBubble(_ answer: String) -> some View {
        Text(answer)
            .font(.system(size: 15.5, weight: .regular, design: .rounded))
            .lineSpacing(5)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .background(glassCardBackground(cornerRadius: 18))
    }

    private func glassCardBackground(cornerRadius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.30), Color.white.opacity(0.08), Color.black.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 0.8)
            )
    }

    private func lookupHeader(_ stack: LookupNavigationStack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            breadcrumb(stack)
            if let node = stack.currentNode {
                Text(node.term)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                Text("Depth \(stack.depth) · \(node.sourceLabel)")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
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
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                    .background(glassCardBackground(cornerRadius: 18))
                }
                if !node.answer.isEmpty {
                    followUpComposer
                }
            }
        }
    }

    private var followUpComposer: some View {
        HStack(spacing: 10) {
            TextField("Ask a follow-up…", text: $viewModel.followUpQuestion)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(glassCardBackground(cornerRadius: 16))
                .onSubmit {
                    viewModel.requestFollowUp()
                }
            Button {
                viewModel.requestFollowUp()
            } label: {
                Text("Ask")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                            .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 0.8))
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(viewModel.followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
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
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Text("\(capture.appName)" + sourceSuffix(capture.source))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func captureDetails(_ capture: CapturedSelection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow("Window", capture.windowTitle.isEmpty ? "Unknown" : capture.windowTitle)
            metadataRow("App", capture.appName)
            metadataRow("Source", capture.source == .accessibility ? "Accessibility API" : "Clipboard fallback")
            if let question = capture.question, !question.isEmpty {
                metadataRow("Question", question)
            }

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
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Text("\(capture.appName) · Buddy Capture")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
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
                        metadataRow("Image", "\(screenshot.pixelWidth)×\(screenshot.pixelHeight), \(screenshot.encodedBytes) bytes")
                        metadataRow("OCR", screenshot.recognizedText.isEmpty ? "No text detected" : "\(screenshot.recognizedText.count) chars")
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
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .rounded))
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
        textView.font = NSFont.systemFont(ofSize: 15.5, weight: .regular)
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
        textView.font = NSFont.systemFont(ofSize: 15.5, weight: .regular)
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
