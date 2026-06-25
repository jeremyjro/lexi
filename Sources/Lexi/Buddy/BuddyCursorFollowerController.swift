import AppKit
import QuartzCore

enum BuddyCursorFollowerActivity: Equatable {
    case idle
    case listening
    case selecting
    case working
    case streaming
    case error

    var isActive: Bool {
        self != .idle
    }
}

@MainActor
final class BuddyCursorFollowerController {
    private var windows: [BuddyCursorFollowerWindow] = []
    private var displayTimer: Timer?
    private var idleTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var currentPosition = CGPoint.zero
    private var velocity = CGPoint.zero
    private var lastTickTime = CACurrentMediaTime()
    private var hasPosition = false
    private var isVisible = false

    func start() {
        guard !isVisible else { return }
        ensureWindows()
        currentPosition = targetPosition()
        velocity = .zero
        hasPosition = true
        lastTickTime = CACurrentMediaTime()
        windows.forEach { window in
            window.state.position = currentPosition
            window.state.activity = .idle
            window.state.animationPhase = 0
            window.orderFrontRegardless()
        }
        isVisible = true
        startTimer()
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
        hintTask?.cancel()
        hintTask = nil
        windows.forEach { $0.state.hintText = "" }
        stopTimer()
        windows.forEach { $0.orderOut(nil) }
        isVisible = false
        hasPosition = false
        velocity = .zero
    }

    func setActivity(_ activity: BuddyCursorFollowerActivity) {
        start()
        idleTask?.cancel()
        idleTask = nil
        windows.forEach { $0.state.activity = activity }
    }

    func settleToIdle(after delay: TimeInterval = 0.7) {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.setActivity(.idle)
        }
    }

    func pulse(_ activity: BuddyCursorFollowerActivity, duration: TimeInterval = 0.9) {
        setActivity(activity)
        settleToIdle(after: duration)
    }

    func showHint(_ text: String, duration: TimeInterval = 3.0) {
        start()
        hintTask?.cancel()
        windows.forEach { $0.state.hintText = text }
        hintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.windows.forEach { $0.state.hintText = "" }
            self?.hintTask = nil
        }
    }

    private func ensureWindows() {
        let screens = NSScreen.screens
        if windows.map(\.screenFrame) == screens.map(\.frame) {
            return
        }
        windows.forEach { $0.close() }
        windows = screens.map { BuddyCursorFollowerWindow(screen: $0) }
    }

    private func startTimer() {
        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tick() {
        ensureWindows()
        let now = CACurrentMediaTime()
        let deltaTime = min(max(now - lastTickTime, 1.0 / 120.0), 1.0 / 20.0)
        lastTickTime = now

        let target = targetPosition()
        if !hasPosition || distance(from: currentPosition, to: target) > 1400 {
            currentPosition = target
            velocity = .zero
            hasPosition = true
        } else {
            let stiffness: CGFloat = 118
            let damping: CGFloat = 19.2
            let delta = CGPoint(x: target.x - currentPosition.x, y: target.y - currentPosition.y)
            velocity.x += delta.x * stiffness * deltaTime
            velocity.y += delta.y * stiffness * deltaTime
            let dampingMultiplier = CGFloat(exp(-Double(damping) * deltaTime))
            velocity.x *= dampingMultiplier
            velocity.y *= dampingMultiplier
            currentPosition.x += velocity.x * deltaTime
            currentPosition.y += velocity.y * deltaTime
        }

        for window in windows {
            window.state.position = currentPosition
            window.state.animationPhase += CGFloat(deltaTime)
        }
    }

    private func targetPosition() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x + 14, y: mouse.y - 13)
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}

@MainActor
private final class BuddyCursorFollowerWindow {
    let state = BuddyCursorFollowerState()
    let screenFrame: CGRect
    private let panel: NSPanel

    init(screen: NSScreen) {
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
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = BuddyCursorFollowerView(state: state, screenFrame: screen.frame)
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
private final class BuddyCursorFollowerState {
    var position = CGPoint.zero { didSet { invalidate() } }
    var activity: BuddyCursorFollowerActivity = .idle { didSet { invalidate() } }
    var hintText = "" { didSet { invalidate() } }
    var animationPhase: CGFloat = 0 { didSet { invalidate() } }
    weak var view: NSView?

    private func invalidate() {
        view?.needsDisplay = true
    }
}

@MainActor
private final class BuddyCursorFollowerView: NSView {
    private let state: BuddyCursorFollowerState
    private let screenFrame: CGRect

    init(state: BuddyCursorFollowerState, screenFrame: CGRect) {
        self.state = state
        self.screenFrame = screenFrame
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard screenFrame.insetBy(dx: -60, dy: -60).contains(state.position) else { return }
        let point = localPoint(state.position)
        if state.activity.isActive {
            drawActiveHalo(at: point)
        }
        drawGlassOrb(at: point)
        if showsHoldWaveform {
            drawWaveform(at: point)
        }
        drawHintIfNeeded(at: point)
    }

    private func drawGlassOrb(at point: CGPoint) {
        let alpha: CGFloat = state.activity.isActive ? 0.96 : 0.74
        let radius: CGFloat = state.activity.isActive ? 7.2 : 6.6
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: rect)
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setShadow(offset: CGSize(width: 0, height: -2), blur: 9, color: NSColor.black.withAlphaComponent(0.18 * alpha).cgColor)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.70 * alpha),
            NSColor(calibratedWhite: 0.92, alpha: 0.34 * alpha),
            activeColor.withAlphaComponent(0.13 * alpha),
            NSColor.white.withAlphaComponent(0.24 * alpha)
        ])?.draw(in: path, angle: -42)
        context?.restoreGState()

        NSColor.white.withAlphaComponent(0.74 * alpha).setStroke()
        path.lineWidth = 0.9
        path.stroke()

        let lowerShade = NSBezierPath(ovalIn: rect.insetBy(dx: 1.4, dy: 1.4))
        NSColor.black.withAlphaComponent(0.045 * alpha).setStroke()
        lowerShade.lineWidth = 0.7
        lowerShade.stroke()

        let glint = NSBezierPath(ovalIn: CGRect(x: point.x - radius * 0.45, y: point.y + radius * 0.18, width: radius * 0.62, height: radius * 0.42))
        NSColor.white.withAlphaComponent(0.80 * alpha).setFill()
        glint.fill()

        let pinpoint = NSBezierPath(ovalIn: CGRect(x: point.x + radius * 0.18, y: point.y + radius * 0.32, width: 1.7, height: 1.7))
        NSColor.white.withAlphaComponent(0.90 * alpha).setFill()
        pinpoint.fill()
    }

    private func drawActiveHalo(at point: CGPoint) {
        let phase = state.animationPhase
        let baseColor = activeColor
        for index in 0..<2 {
            let progress = CGFloat((phase * 0.92 + Double(index) * 0.43).truncatingRemainder(dividingBy: 1))
            let radius = 9 + progress * 11
            let alpha = (1 - progress) * 0.20
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            let path = NSBezierPath(ovalIn: rect)
            baseColor.withAlphaComponent(alpha).setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }
    }

    private func drawWaveform(at point: CGPoint) {
        let phase = state.animationPhase * 8
        let baseX = point.x + 9
        let baseY = point.y - 1
        for index in 0..<3 {
            let offset = CGFloat(index) * 3.6
            let wave = CGFloat((sin(Double(phase + CGFloat(index) * 0.88)) + 1) / 2)
            let height = 4.4 + wave * 8.2
            let rect = CGRect(x: baseX + offset, y: baseY - height / 2, width: 2.1, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.1, yRadius: 1.1)
            activeColor.withAlphaComponent(0.42 + wave * 0.38).setFill()
            path.fill()
        }
    }

    private func drawHintIfNeeded(at point: CGPoint) {
        let trimmed = state.hintText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.92),
        ]
        let attributed = NSAttributedString(string: trimmed, attributes: attributes)
        var size = attributed.boundingRect(
            with: NSSize(width: 260, height: 42),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        size.width = ceil(min(260, size.width + 22))
        size.height = ceil(size.height + 14)

        var origin = CGPoint(x: point.x + 22, y: point.y - size.height / 2)
        origin.x = min(max(origin.x, 12), bounds.width - size.width - 12)
        origin.y = min(max(origin.y, 12), bounds.height - size.height - 12)
        let rect = CGRect(origin: origin, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setShadow(offset: CGSize(width: 0, height: -2), blur: 12, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.72),
            NSColor(calibratedWhite: 0.96, alpha: 0.46),
            NSColor.white.withAlphaComponent(0.30)
        ])?.draw(in: path, angle: -42)
        context?.restoreGState()
        NSColor.white.withAlphaComponent(0.62).setStroke()
        path.lineWidth = 0.8
        path.stroke()
        attributed.draw(with: rect.insetBy(dx: 11, dy: 7), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private var showsHoldWaveform: Bool {
        state.activity == .listening || state.activity == .selecting
    }

    private var activeColor: NSColor {
        switch state.activity {
        case .idle:
            return NSColor(calibratedWhite: 0.94, alpha: 1)
        case .listening:
            return NSColor(calibratedRed: 0.78, green: 0.94, blue: 0.92, alpha: 1)
        case .selecting:
            return NSColor(calibratedWhite: 0.96, alpha: 1)
        case .working:
            return NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        case .streaming:
            return NSColor(calibratedRed: 0.90, green: 0.86, blue: 0.96, alpha: 1)
        case .error:
            return NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.38, alpha: 1)
        }
    }

    private func localPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: point.y - screenFrame.minY)
    }
}
