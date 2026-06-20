import Cocoa
import SwiftUI

class CursorFollowerWindow: NSWindow {
    private var hostingController: NSHostingController<CursorFollowerView>?
    private var trackingTimer: Timer?
    private var state: CursorFollowerState = .idle
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        
        let cursorView = CursorFollowerView(state: state)
        hostingController = NSHostingController(rootView: cursorView)
        self.contentViewController = hostingController
        
        position(at: NSEvent.mouseLocation)
        self.orderFrontRegardless()
    }
    
    convenience init() {
        self.init(contentRect: NSRect.zero, styleMask: .borderless, backing: .buffered, defer: false)
    }
    
    func startFollowing() {
        // Update position every 16ms (~60fps)
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
    }
    
    func stopFollowing() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }
    
    private func updatePosition() {
        let mouseLocation = NSEvent.mouseLocation
        position(at: mouseLocation)
    }
    
    func position(at point: NSPoint) {
        // Position slightly offset from cursor to not interfere
        let offset: CGFloat = 25
        var origin = point
        origin.x += offset
        origin.y += offset
        
        // Keep on screen
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let screenFrame = screen?.visibleFrame {
            origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - 40))
            origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - 40))
        }
        
        self.setFrameOrigin(origin)
    }
    
    func updateState(_ newState: CursorFollowerState) {
        state = newState
        hostingController?.rootView = CursorFollowerView(state: state)
    }
    
    func showResultBubble(at position: NSPoint, explanation: String, onClose: @escaping () -> Void) {
        // This will be handled by the main bubble controller
        // The cursor follower just shows the state
    }
}