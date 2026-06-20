import Cocoa
import SwiftUI

class BubbleController {
    private var bubbleWindow: BubbleWindow?
    private var currentState: BubbleState = .hidden
    private var retryCallback: (() -> Void)?
    
    init() {
        bubbleWindow = BubbleWindow()
    }
    
    func showBubble(at position: NSPoint, state: BubbleState, onRetry: (() -> Void)? = nil, onClose: (() -> Void)? = nil, onTextSelected: ((String) -> Void)? = nil, onFollowUpPrompt: ((String, @escaping () -> Void) -> Void)? = nil) {
        print("🫧 showBubble called with state: \(state)")
        currentState = state
        retryCallback = onRetry
        
        guard state.isVisible else {
            print("❌ State is hidden, not showing bubble")
            hideBubble()
            return
        }
        
        print("✅ Showing bubble with visible state")
        
        // Set the text selected callback on the window
        if let onTextSelected = onTextSelected {
            bubbleWindow?.setTextSelectedCallback(onTextSelected)
        }
        
        bubbleWindow?.updateContent(state: state, onRetry: onRetry, onClose: onClose, onTextSelected: onTextSelected, onFollowUpPrompt: onFollowUpPrompt)
        bubbleWindow?.position(at: position, state: state)
        bubbleWindow?.makeKeyAndOrderFront(nil)
        bubbleWindow?.orderFrontRegardless()
        // Force the window to become key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.bubbleWindow?.makeKey()
        }
    }
    
    func isBubbleVisible() -> Bool {
        return currentState.isVisible
    }
    
    func updateStreamingContent(_ content: String) {
        print("🔄 BubbleController: Updating streaming content: \(content.count) characters")
        print("📝 Content preview: '\(String(content.prefix(200)))'")
        currentState = .streaming(content)
        bubbleWindow?.updateStreamingContent(content)
    }
    
    func showProcessingFeedback() {
        // No cursor follower, so no feedback needed
    }
    
    func updateCursorFollowerOnly(state: BubbleState) {
        // No cursor follower, so no update needed
    }
    
    func hideBubble() {
        bubbleWindow?.orderOut(nil)
        currentState = .hidden
    }
    
    func updatePosition(_ position: NSPoint) {
        guard currentState.isVisible else { return }
        bubbleWindow?.position(at: position, state: currentState)
    }
    
    func getCurrentState() -> BubbleState {
        return currentState
    }
}

class BubbleWindow: NSWindow {
    private let viewModel = BubbleViewModel()
    private var hostingController: NSHostingController<BubbleView>?
    private var initialLocation: NSPoint?
    private var isOptionCommandHeld = false
    private var onTextSelected: ((String) -> Void)?
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 800),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.collectionBehavior = [.fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.hasShadow = true
        self.titlebarAppearsTransparent = true
        self.isMovable = false
        self.isMovableByWindowBackground = false
        
        // Set minimum size
        self.minSize = NSSize(width: 320, height: 400)
        
        let bubbleView = BubbleView(viewModel: viewModel)
        hostingController = NSHostingController(rootView: bubbleView)
        self.contentViewController = hostingController
        
        if let view = hostingController?.view {
            view.wantsLayer = true
            view.layer?.cornerRadius = 24
            view.layer?.masksToBounds = true
        }
        
        // Set initial position
        position(at: NSPoint(x: 0, y: 0), state: .hidden)
        
        // Enable dragging and key monitoring
        self.makeDraggable()
        self.setupKeyMonitoring()
    }
    
    private func makeDraggable() {
        // Enable mouse move tracking for dragging
        self.acceptsMouseMovedEvents = true
    }
    
    private func setupKeyMonitoring() {
        // Use global monitor instead of local to ensure we catch key events
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }

            // Only process if our window is visible
            guard self.isVisible else { return }

            let optionHeld = event.modifierFlags.contains(.option)
            let commandHeld = event.modifierFlags.contains(.command)
            let bothHeld = optionHeld && commandHeld

            if bothHeld && !self.isOptionCommandHeld {
                self.isOptionCommandHeld = true
                print("🔹 Option+Command detected in bubble window (global)")
            } else if !bothHeld && self.isOptionCommandHeld {
                self.isOptionCommandHeld = false
                print("🔹 Option+Command released in bubble window (global)")

                // Check for text selection when keys are released
                self.checkForTextSelection()
            }
        }
    }
    
    private func checkForTextSelection() {
        // Get selected text from pasteboard (macOS standard selection method)
        let pasteboard = NSPasteboard.general
        if let selectedText = pasteboard.string(forType: .string), !selectedText.isEmpty {
            print("📝 Text selected in bubble: '\(selectedText)'")
            onTextSelected?(selectedText)
        }
    }
    
    func setTextSelectedCallback(_ callback: @escaping (String) -> Void) {
        self.onTextSelected = callback
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Don't enable dragging - keep window fixed
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let initialLocation = initialLocation else { return }
        
        let newLocation = event.locationInWindow
        let deltaX = newLocation.x - initialLocation.x
        let deltaY = newLocation.y - initialLocation.y
        
        var newOrigin = self.frame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        
        self.setFrameOrigin(newOrigin)
    }
    
    func updateContent(state: BubbleState, onRetry: (() -> Void)? = nil, onClose: (() -> Void)? = nil, onTextSelected: ((String) -> Void)? = nil, onFollowUpPrompt: ((String, @escaping () -> Void) -> Void)? = nil) {
        DispatchQueue.main.async {
            self.viewModel.apply(
                state: state,
                onRetry: onRetry,
                onClose: onClose,
                onTextSelected: onTextSelected,
                onFollowUpPrompt: onFollowUpPrompt
            )
        }
    }
    
    func updateStreamingContent(_ content: String) {
        DispatchQueue.main.async {
            self.viewModel.updateStreamingContent(content)
        }
    }
    
    func position(at point: NSPoint, state: BubbleState) {
        // Position bubble at bottom center of screen (Wispr Flow style)
        let screen = NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect.zero
        
        // Calculate size based on state
        let bubbleHeight: CGFloat
        let bubbleWidth: CGFloat
        
        switch state {
        case .capturing:
            // Small compact size for capturing
            bubbleHeight = 50
            bubbleWidth = 160
        default:
            // Wispr Flow style - compact oval overlay
            bubbleHeight = 450  // Increased height for content
            bubbleWidth = 420   // Slightly wider for readability
        }
        
        // Bottom center positioning
        let origin = NSPoint(
            x: screenFrame.midX - bubbleWidth / 2,
            y: screenFrame.minY + 40
        )
        
        // Set both frame and content size
        let newFrame = NSRect(origin: origin, size: NSSize(width: bubbleWidth, height: bubbleHeight))
        self.setFrame(newFrame, display: true, animate: true)
    }
}