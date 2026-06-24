import AppKit
import ApplicationServices

struct BuddyCaptureContext {
    let question: String
    let screenshot: RegionScreenshot?
    let appName: String
    let windowTitle: String
    let anchorRect: CGRect?

    var displayTitle: String {
        question.isEmpty ? "Buddy Capture" : question
    }

    var sourceText: String {
        var parts: [String] = []
        if !question.isEmpty {
            parts.append("Question: \(question)")
        }
        if let screenshot {
            parts.append("Screenshot: \(screenshot.pixelWidth)×\(screenshot.pixelHeight) region")
        }
        return parts.isEmpty ? "Buddy Capture" : parts.joined(separator: "\n")
    }
}

@MainActor
final class BuddyCaptureCoordinator {
    var isEnabledProvider: () -> Bool = { true }
    var onCaptureReady: ((BuddyCaptureContext) -> Void)?
    var onCaptureCancelled: (() -> Void)?
    var onPermissionsMissing: (([BuddyPermission]) -> Void)?
    var onError: ((String) -> Void)?
    var onInstallFailed: (() -> Void)?

    private let hotkeyMonitor = BuddyHotkeyMonitor()
    private let overlay = BuddyOverlayController()
    private let voiceCapture = BuddyVoiceCapture()
    private var metadata = BuddyWindowMetadata(appName: "Unknown", windowTitle: "")
    private var isCapturing = false
    private var isSelecting = false
    private var finalizeTask: Task<Void, Never>?

    init() {
        hotkeyMonitor.onBegin = { [weak self] location in
            self?.begin(at: location)
        }
        overlay.onSelectionFinished = { [weak self] location in
            self?.finish(at: location)
        }
        hotkeyMonitor.onCancel = { [weak self] in
            self?.cancel()
        }
        hotkeyMonitor.onInstallFailed = { [weak self] in
            self?.onInstallFailed?()
        }
    }

    func start() {
        hotkeyMonitor.start()
    }

    func stop() {
        finalizeTask?.cancel()
        hotkeyMonitor.stop()
        cancel()
    }

    func cancelActiveCapture() {
        hotkeyMonitor.cancelActiveCapture()
        cancel()
    }

    func beginCaptureFromUI() {
        begin(at: NSEvent.mouseLocation)
    }

    private func begin(at location: CGPoint) {
        guard isEnabledProvider() else { return }
        guard !isCapturing else { return }

        finalizeTask?.cancel()
        metadata = currentWindowMetadata()
        isCapturing = true
        isSelecting = false
        overlay.show(at: location)

        if BuddyPermissions.status(.microphone).isGranted,
           BuddyPermissions.status(.speechRecognition).isGranted {
            do {
                try voiceCapture.start { [weak self] transcript in
                    self?.overlay.updateTranscript(transcript)
                }
            } catch {
                overlay.updateTranscript("Voice unavailable; drag to capture")
            }
        } else {
            overlay.updateTranscript("Drag to capture; voice is off until Mic + Speech are enabled")
        }
    }

    private func beginSelection(at location: CGPoint) {
        guard isCapturing else { return }
        isSelecting = true
        overlay.beginSelection(at: location)
    }

    private func updateSelection(to location: CGPoint) {
        guard isCapturing else { return }
        overlay.updateSelection(to: location)
    }

    private func endSelection(at location: CGPoint) {
        guard isCapturing else { return }
        isSelecting = false
        overlay.endSelection(at: location)
    }

    private func finish(at location: CGPoint) {
        guard isCapturing else { return }
        if isSelecting {
            overlay.endSelection(at: location)
            isSelecting = false
        }

        let region = overlay.selectedRegion
        guard region != nil else {
            cancel()
            return
        }
        let captureMetadata = metadata
        hotkeyMonitor.completeActiveCapture()
        isCapturing = false

        finalizeTask?.cancel()
        finalizeTask = Task { [weak self] in
            guard let self else { return }
            let question = await self.voiceCapture.stop()
            guard !Task.isCancelled else { return }

            var screenshot: RegionScreenshot?
            do {
                if let region {
                    screenshot = try await RegionScreenshotCapture.captureRegion(region)
                } else {
                    screenshot = try await RegionScreenshotCapture.captureFocusedWindow()
                }
            } catch {
                if question.isEmpty {
                    await MainActor.run {
                        self.overlay.hide()
                        self.onError?(error.localizedDescription)
                    }
                    return
                }
            }

            await MainActor.run {
                self.overlay.hide()
                guard !question.isEmpty || screenshot != nil else {
                    self.onCaptureCancelled?()
                    return
                }
                self.onCaptureReady?(BuddyCaptureContext(
                    question: question,
                    screenshot: screenshot,
                    appName: captureMetadata.appName,
                    windowTitle: captureMetadata.windowTitle,
                    anchorRect: region
                ))
            }
        }
    }

    private func cancel() {
        finalizeTask?.cancel()
        finalizeTask = nil
        isCapturing = false
        isSelecting = false
        voiceCapture.cancel()
        overlay.hide()
        onCaptureCancelled?()
    }

    private func missingBuddyPermissions() -> [BuddyPermission] {
        [.screenRecording, .microphone, .speechRecognition].filter { !BuddyPermissions.status($0).isGranted }
    }

    private func currentWindowMetadata() -> BuddyWindowMetadata {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else {
            return BuddyWindowMetadata(appName: appName, windowTitle: "")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedWindow = focusedWindow(from: appElement),
              let title = stringAttribute(kAXTitleAttribute, from: focusedWindow) else {
            return BuddyWindowMetadata(appName: appName, windowTitle: "")
        }

        return BuddyWindowMetadata(appName: appName, windowTitle: title)
    }

    private func focusedWindow(from appElement: AXUIElement) -> AXUIElement? {
        var focusedWindow: AnyObject?
        let error = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard error == .success, let focusedWindow else { return nil }
        return focusedWindow as! AXUIElement?
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? String
    }
}

private struct BuddyWindowMetadata {
    let appName: String
    let windowTitle: String
}
