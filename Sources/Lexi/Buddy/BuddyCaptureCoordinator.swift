import AppKit
import ApplicationServices

struct BuddyCaptureContext {
    let question: String
    let screenshot: RegionScreenshot?
    let appName: String
    let windowTitle: String
    let anchorRect: CGRect?
    let modeLabel: String
    let textContext: String

    var displayTitle: String {
        question.isEmpty ? "Buddy Capture" : question
    }

    var sourceText: String {
        var parts: [String] = []
        if !question.isEmpty {
            parts.append("Question: \(question)")
        }
        if let screenshot {
            parts.append("Screenshot: \(screenshot.pixelWidth)×\(screenshot.pixelHeight), \(screenshot.encodedBytes) bytes")
            if !screenshot.recognizedText.isEmpty {
                parts.append("OCR: \(screenshot.recognizedText)")
            }
        }
        if !textContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Text context: \(textContext)")
        }
        parts.append("Mode: \(modeLabel)")
        return parts.isEmpty ? "Buddy Capture" : parts.joined(separator: "\n")
    }
}

@MainActor
final class BuddyCaptureCoordinator {
    var isEnabledProvider: () -> Bool = { true }
    var onCaptureReady: ((BuddyCaptureContext) -> Void)?
    var onCaptureCancelled: (() -> Void)?
    var onPermissionsMissing: (([BuddyPermission]) -> Void)?
    var onMessage: ((String, String) -> Void)?
    var onActivityChanged: ((BuddyCursorFollowerActivity) -> Void)?
    var onCursorHint: ((String, TimeInterval) -> Void)?
    var onError: ((String) -> Void)?
    var onInstallFailed: (() -> Void)?
    var contextualKeytermsProvider: () -> [String] = { [] }

    private let hotkeyMonitor = BuddyHotkeyMonitor()
    private let pushToTalkMonitor = BuddyPushToTalkMonitor()
    private let overlay = BuddyOverlayController()
    private let voiceCapture = BuddyVoiceCapture()
    private var metadata = BuddyWindowMetadata(appName: "Unknown", windowTitle: "")
    private var isCapturing = false
    private var isQuickCapturing = false
    private var isSelecting = false
    private var waitsForModifierRelease = false
    private var finalizeTask: Task<Void, Never>?

    init() {
        hotkeyMonitor.onBegin = { [weak self] location in
            self?.begin(at: location, waitsForModifierRelease: true)
        }
        hotkeyMonitor.onEnd = { [weak self] location in
            self?.finish(at: location)
        }
        overlay.onSelectionFinished = { [weak self] location in
            guard let self else { return }
            if self.waitsForModifierRelease {
                self.endSelection(at: location)
            } else {
                self.finish(at: location)
            }
        }
        hotkeyMonitor.onCancel = { [weak self] in
            self?.cancel()
        }
        hotkeyMonitor.onInstallFailed = { [weak self] in
            self?.onInstallFailed?()
        }
        pushToTalkMonitor.onPressed = { [weak self] in
            self?.beginQuickCapture()
        }
        pushToTalkMonitor.onReleased = { [weak self] in
            self?.finishQuickCapture()
        }
        pushToTalkMonitor.onInstallFailed = { [weak self] in
            self?.onInstallFailed?()
        }
    }

    func start() {
        hotkeyMonitor.start()
        pushToTalkMonitor.start()
    }

    func stop() {
        finalizeTask?.cancel()
        hotkeyMonitor.stop()
        pushToTalkMonitor.stop()
        cancel()
    }

    func cancelActiveCapture() {
        hotkeyMonitor.cancelActiveCapture()
        cancel()
    }

    func beginCaptureFromUI() {
        begin(at: NSEvent.mouseLocation, waitsForModifierRelease: false)
    }

    private func begin(at location: CGPoint, waitsForModifierRelease: Bool) {
        guard isEnabledProvider() else { return }
        guard !isCapturing, !isQuickCapturing else { return }

        finalizeTask?.cancel()
        metadata = currentWindowMetadata()
        isCapturing = true
        isQuickCapturing = false
        isSelecting = false
        self.waitsForModifierRelease = waitsForModifierRelease
        overlay.show(at: location)
        onActivityChanged?(.selecting)
        onCursorHint?("Drag anywhere on the screen to capture", 3.0)

        if BuddyPermissions.status(.microphone).isGranted,
           AppConfiguration.voiceProvider == .assemblyAI || BuddyPermissions.status(.speechRecognition).isGranted {
            do {
                try voiceCapture.start(keyterms: contextualKeytermsProvider()) { [weak self] transcript in
                    self?.overlay.updateTranscript(transcript)
                }
            } catch {
                overlay.updateTranscript("Voice unavailable; drag to capture")
            }
        } else {
            overlay.updateTranscript("Drag to capture; voice is off until required permissions are enabled")
        }
    }

    private func beginQuickCapture() {
        guard isEnabledProvider() else { return }
        guard !isCapturing, !isQuickCapturing else { return }
        guard BuddyPermissions.status(.microphone).isGranted else {
            onError?("Microphone permission is required for push-to-talk Buddy Capture.")
            return
        }
        guard AppConfiguration.voiceProvider == .assemblyAI || BuddyPermissions.status(.speechRecognition).isGranted else {
            onError?("Speech Recognition permission is required for Apple Speech. Switch to AssemblyAI after configuring the proxy, or enable Speech Recognition.")
            return
        }

        finalizeTask?.cancel()
        metadata = currentWindowMetadata()
        isQuickCapturing = true
        onActivityChanged?(.listening)
        onMessage?("Listening", "Speak your question, then release Control + Option.")
        do {
            try voiceCapture.start(keyterms: contextualKeytermsProvider()) { [weak self] transcript in
                self?.onMessage?("Listening", transcript.isEmpty ? "Listening…" : transcript)
            }
        } catch {
            isQuickCapturing = false
            onActivityChanged?(.error)
            onError?(error.localizedDescription)
        }
    }

    private func finishQuickCapture() {
        guard isQuickCapturing else { return }
        isQuickCapturing = false
        let captureMetadata = metadata
        onActivityChanged?(.working)
        onMessage?("Finalizing", "Transcribing and capturing your current screen context…")
        finalizeTask?.cancel()
        finalizeTask = Task { [weak self] in
            guard let self else { return }
            let question = await self.voiceCapture.stop()
            guard !Task.isCancelled else { return }

            var screenshot: RegionScreenshot?
            do {
                if let focusedWindow = try await RegionScreenshotCapture.captureFocusedWindow() {
                    screenshot = focusedWindow
                } else {
                    screenshot = try await RegionScreenshotCapture.captureCursorScreen()
                }
            } catch {
                if question.isEmpty {
                    await MainActor.run {
                        self.onActivityChanged?(.error)
                        self.onError?(error.localizedDescription)
                    }
                    return
                }
            }

            await MainActor.run {
                guard !question.isEmpty || screenshot != nil else {
                    self.onActivityChanged?(.idle)
                    self.onCaptureCancelled?()
                    return
                }
                self.onCaptureReady?(BuddyCaptureContext(
                    question: question,
                    screenshot: screenshot,
                    appName: captureMetadata.appName,
                    windowTitle: captureMetadata.windowTitle,
                    anchorRect: screenshot?.sourceRect,
                    modeLabel: "Quick Push-to-Talk",
                    textContext: ""
                ))
            }
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

        guard let region = overlay.selectedRegion else {
            cancel()
            return
        }
        let captureMetadata = metadata
        hotkeyMonitor.completeActiveCapture()
        isCapturing = false
        waitsForModifierRelease = false
        onActivityChanged?(.working)

        finalizeTask?.cancel()
        finalizeTask = Task { [weak self] in
            guard let self else { return }
            let question = await self.voiceCapture.stop()
            guard !Task.isCancelled else { return }

            var screenshot: RegionScreenshot?
            do {
                screenshot = try await RegionScreenshotCapture.captureRegion(region)
            } catch {
                if question.isEmpty {
                    await MainActor.run {
                        self.overlay.hide()
                        self.onActivityChanged?(.error)
                        self.onError?(error.localizedDescription)
                    }
                    return
                }
            }

            await MainActor.run {
                self.overlay.hide()
                guard !question.isEmpty || screenshot != nil else {
                    self.onActivityChanged?(.idle)
                    self.onCaptureCancelled?()
                    return
                }
                self.onCaptureReady?(BuddyCaptureContext(
                    question: question,
                    screenshot: screenshot,
                    appName: captureMetadata.appName,
                    windowTitle: captureMetadata.windowTitle,
                    anchorRect: region,
                    modeLabel: "Precise Region",
                    textContext: ""
                ))
            }
        }
    }

    private func cancel() {
        finalizeTask?.cancel()
        finalizeTask = nil
        isCapturing = false
        isQuickCapturing = false
        isSelecting = false
        waitsForModifierRelease = false
        voiceCapture.cancel()
        overlay.hide()
        onActivityChanged?(.idle)
        onCaptureCancelled?()
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
