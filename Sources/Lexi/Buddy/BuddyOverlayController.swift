import AppKit

@MainActor
final class BuddyOverlayController {
    var onSelectionFinished: ((CGPoint) -> Void)?

    private var windows: [BuddyOverlayWindow] = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private(set) var selectedRegion: CGRect?

    var isVisible: Bool {
        windows.contains { $0.isVisible }
    }

    func show(at location: CGPoint) {
        ensureWindows()
        selectedRegion = nil
        dragStart = nil
        dragCurrent = nil
        windows.forEach {
            $0.state.cursorLocation = location
            $0.state.selectionRect = nil
            $0.state.transcript = ""
            $0.orderFrontRegardless()
        }
        NSCursor.crosshair.set()
    }

    func updateCursor(_ location: CGPoint) {
        windows.forEach { $0.state.cursorLocation = location }
    }

    func updateTranscript(_ transcript: String) {
        windows.forEach { $0.state.transcript = transcript }
    }

    func beginSelection(at location: CGPoint) {
        dragStart = location
        dragCurrent = location
        selectedRegion = nil
        updateSelectionRect()
    }

    func updateSelection(to location: CGPoint) {
        dragCurrent = location
        updateSelectionRect()
    }

    func endSelection(at location: CGPoint) {
        dragCurrent = location
        updateSelectionRect()
        selectedRegion = normalizedSelectionRect()
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        dragStart = nil
        dragCurrent = nil
        selectedRegion = nil
        NSCursor.arrow.set()
    }

    private func ensureWindows() {
        let screens = NSScreen.screens
        if windows.map(\.screenFrame) == screens.map(\.frame) {
            return
        }
        windows.forEach { $0.close() }
        windows = screens.map { screen in
            BuddyOverlayWindow(
                screen: screen,
                onMouseDown: { [weak self] location in
                    self?.updateCursor(location)
                    self?.beginSelection(at: location)
                },
                onMouseDragged: { [weak self] location in
                    self?.updateCursor(location)
                    self?.updateSelection(to: location)
                },
                onMouseUp: { [weak self] location in
                    guard let self else { return }
                    self.updateCursor(location)
                    self.endSelection(at: location)
                    self.onSelectionFinished?(location)
                }
            )
        }
    }

    private func updateSelectionRect() {
        let rect = normalizedSelectionRect()
        windows.forEach { $0.state.selectionRect = rect }
    }

    private func normalizedSelectionRect() -> CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        let rect = CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
        guard rect.width >= RegionScreenshotCapture.minRegionSize,
              rect.height >= RegionScreenshotCapture.minRegionSize else {
            return nil
        }
        return rect
    }
}

@MainActor
private final class BuddyOverlayWindow {
    let state = BuddyOverlayState()
    let screenFrame: CGRect
    private let panel: NSPanel

    init(
        screen: NSScreen,
        onMouseDown: @escaping @MainActor (CGPoint) -> Void,
        onMouseDragged: @escaping @MainActor (CGPoint) -> Void,
        onMouseUp: @escaping @MainActor (CGPoint) -> Void
    ) {
        screenFrame = screen.frame
        panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(screen.frame, display: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = BuddyOverlayView(
            state: state,
            screenFrame: screen.frame,
            onMouseDown: onMouseDown,
            onMouseDragged: onMouseDragged,
            onMouseUp: onMouseUp
        )
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func orderFrontRegardless() {
        panel.orderFrontRegardless()
    }

    func orderOut(_ sender: Any?) {
        panel.orderOut(sender)
    }

    func close() {
        panel.close()
    }
}

@MainActor
private final class BuddyOverlayState {
    var cursorLocation: CGPoint = .zero { didSet { invalidate() } }
    var selectionRect: CGRect? { didSet { invalidate() } }
    var transcript = "" { didSet { invalidate() } }
    weak var view: NSView?

    private func invalidate() {
        view?.needsDisplay = true
    }
}

@MainActor
private final class BuddyOverlayView: NSView {
    private let state: BuddyOverlayState
    private let screenFrame: CGRect
    private let onMouseDown: @MainActor (CGPoint) -> Void
    private let onMouseDragged: @MainActor (CGPoint) -> Void
    private let onMouseUp: @MainActor (CGPoint) -> Void

    init(
        state: BuddyOverlayState,
        screenFrame: CGRect,
        onMouseDown: @escaping @MainActor (CGPoint) -> Void,
        onMouseDragged: @escaping @MainActor (CGPoint) -> Void,
        onMouseUp: @escaping @MainActor (CGPoint) -> Void
    ) {
        self.state = state
        self.screenFrame = screenFrame
        self.onMouseDown = onMouseDown
        self.onMouseDragged = onMouseDragged
        self.onMouseUp = onMouseUp
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        state.view = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown(screenPoint(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged(screenPoint(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp(screenPoint(from: event))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawScrim()
        drawSelection()
        drawOrb()
    }

    private func drawScrim() {
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()
    }

    private func drawSelection() {
        guard let selection = state.selectionRect?.intersection(screenFrame), !selection.isNull else { return }
        let rect = localRect(selection)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.86).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func drawOrb() {
        guard screenFrame.contains(state.cursorLocation) else { return }
        let point = localPoint(state.cursorLocation)
        let radius: CGFloat = 18
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: rect)
        NSColor.systemBlue.withAlphaComponent(0.92).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2
        path.stroke()

        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 9, dy: 9))
        NSColor.white.withAlphaComponent(0.92).setFill()
        inner.fill()

        let text = state.transcript.isEmpty ? "Drag to capture; release to ask" : state.transcript
        drawCaption(text, near: point)
    }

    private func drawCaption(_ text: String, near point: CGPoint) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmed.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attributed = NSAttributedString(string: trimmed, attributes: attributes)
        let maxWidth: CGFloat = 300
        var size = attributed.boundingRect(
            with: NSSize(width: maxWidth, height: 60),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        size.width = ceil(min(maxWidth, size.width + 18))
        size.height = ceil(size.height + 12)

        var origin = CGPoint(x: point.x + 24, y: point.y - size.height / 2)
        origin.x = min(max(origin.x, 10), bounds.width - size.width - 10)
        origin.y = min(max(origin.y, 10), bounds.height - size.height - 10)

        let bubble = CGRect(origin: origin, size: size)
        let path = NSBezierPath(roundedRect: bubble, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.72).setFill()
        path.fill()
        attributed.draw(with: bubble.insetBy(dx: 9, dy: 6), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func screenPoint(from event: NSEvent) -> CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        let point = event.locationInWindow
        return CGPoint(x: window.frame.minX + point.x, y: window.frame.minY + point.y)
    }

    private func localPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: point.y - screenFrame.minY)
    }

    private func localRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: rect.minY - screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }
}
