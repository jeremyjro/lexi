import AppKit
import ApplicationServices
import Foundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionOnboarding: PermissionOnboardingWindowController?
    private let hotkeyManager = HotkeyManager()
    private let selectionCapture = SelectionCapture()
    private let rawCapturePanel = RawCapturePanelController()
    private let sessionMemory = ResearchSessionMemory()
    private let ttsClient = ElevenLabsTTSClient()
    private let highlightVoiceCapture = BuddyVoiceCapture()
    private let calloutOverlay = BuddyCalloutOverlayController()
    private let cursorBuddy = BuddyCursorFollowerController()
    private var buddyCoordinator: BuddyCaptureCoordinator?
    private var settingsWindow: SettingsWindowController?
    private var explainTask: Task<Void, Never>?
    private var lastAnswer: String?
    private var isLookupHotkeyHeld = false
    private var isHighlightVoiceCaptureArmed = false
    private var isEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        cursorBuddy.start()
        rawCapturePanel.onDismiss = { [weak self] in
            self?.explainTask?.cancel()
        }
        rawCapturePanel.onNestedLookupRequested = { [weak self] term, stack in
            self?.requestNestedExplanation(term: term, stack: stack)
        }
        rawCapturePanel.onFollowUpRequested = { [weak self] question, stack in
            self?.requestFollowUp(question: question, stack: stack)
        }
        setupBuddyCapture()

        requestAccessibilityPermission()
        let isTrusted = AXIsProcessTrusted()
        print("Accessibility trusted: \(isTrusted)")

        if !isTrusted {
            print("Accessibility permission is not enabled")
            showPermissionOnboarding()
        }

        setupGlobalHotkey()
        showSettings()
        print("Lexi started successfully")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Lexi"
        item.button?.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Lexi")
        item.button?.imagePosition = .imageLeading
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let enableItem = NSMenuItem(title: isEnabled ? "Disable" : "Enable", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        menu.addItem(enableItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let hotkeyItem = NSMenuItem(title: "Hotkeys…", action: #selector(showHotkeyInfo), keyEquivalent: "")
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)

        let buddyItem = NSMenuItem(title: "Start Buddy Capture", action: #selector(startBuddyCaptureFromMenu), keyEquivalent: "")
        buddyItem.target = self
        buddyItem.isEnabled = isEnabled
        menu.addItem(buddyItem)

        let permissionItem = NSMenuItem(title: "Re-check Permissions", action: #selector(recheckPermission), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let proxyItem = NSMenuItem(title: "Check Proxy Status", action: #selector(checkProxyStatus), keyEquivalent: "")
        proxyItem.target = self
        menu.addItem(proxyItem)

        let copyAnswerItem = NSMenuItem(title: "Copy Last Answer", action: #selector(copyLastAnswer), keyEquivalent: "c")
        copyAnswerItem.target = self
        copyAnswerItem.isEnabled = lastAnswer?.isEmpty == false
        menu.addItem(copyAnswerItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Lexi", action: #selector(quitLexi), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func showPermissionOnboarding() {
        if permissionOnboarding == nil {
            permissionOnboarding = PermissionOnboardingWindowController()
        }
        permissionOnboarding?.showWindow(nil)
        permissionOnboarding?.window?.orderFrontRegardless()
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if !isEnabled {
            isLookupHotkeyHeld = false
            isHighlightVoiceCaptureArmed = false
            explainTask?.cancel()
            ttsClient.stop()
            highlightVoiceCapture.cancel()
            calloutOverlay.hide()
            cursorBuddy.stop()
            buddyCoordinator?.cancelActiveCapture()
            rawCapturePanel.hide()
        } else {
            cursorBuddy.start()
            cursorBuddy.setActivity(.idle)
        }
        rebuildMenu()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(onStartBuddyCapture: { [weak self] in
                self?.startBuddyCapture()
            })
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showHotkeyInfo() {
        showAlert(
            title: "Lexi hotkeys",
            message: "Hold Option + Space while selecting text, optionally speak a question, then release. If you do not speak, Lexi infers the most useful explanation from the highlight. Hold Option + Command while dragging a screen region, then release the keys to submit it; releasing before any region exists cancels. Hold Control + Option to ask a quick Buddy question; release to capture the focused window or cursor screen. Inside a Lexi answer, type a follow-up or highlight a phrase and press →. Use ← to pop up and Esc to close."
        )
    }

    func startBuddyCapture() {
        guard let buddyCoordinator else {
            cursorBuddy.pulse(.error)
            rawCapturePanel.show(status: .buddyError(nil, "Buddy Capture is not initialized. Quit and reopen Lexi."), anchorRect: nil)
            return
        }
        cursorBuddy.setActivity(.working)
        cursorBuddy.showHint("Drag anywhere on the screen to capture", duration: 3.0)
        buddyCoordinator.beginCaptureFromUI()
    }

    @objc private func startBuddyCaptureFromMenu() {
        startBuddyCapture()
    }

    @objc private func recheckPermission() {
        if BuddyPermissions.allGranted {
            showAlert(title: "Lexi permissions are enabled")
        } else {
            requestAccessibilityPermission()
            showPermissionOnboarding()
        }
    }

    @objc private func checkProxyStatus() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let client = ExplainClient()
                let health = try await client.health()
                await MainActor.run {
                    let backendKeyStatus = health.anthropicApiKeyConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                    let backendTokenStatus = health.proxyTokenConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                    let assemblyStatus = health.assemblyAIConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                    let elevenLabsStatus = health.elevenLabsConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                    let perplexityStatus = health.perplexityConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                    self.showAlert(
                        title: health.ok ? "Lexi proxy is online" : "Lexi proxy responded unexpectedly",
                        message: "URL: \(client.baseURLDescription)\nModel: \(health.model)\nVision model: \(health.visionModel ?? health.model)\nLocal token configured: \(client.hasProxyToken ? "Yes" : "No")\nBackend key configured: \(backendKeyStatus)\nBackend token configured: \(backendTokenStatus)\nAssemblyAI configured: \(assemblyStatus)\nElevenLabs configured: \(elevenLabsStatus)\nPerplexity configured: \(perplexityStatus)\nResearch provider: \(health.researchProvider ?? "none")\nResearch mode: \(health.researchMode ?? "unknown")\nResearch model: \(health.perplexityModel ?? "unknown")"
                    )
                }
            } catch {
                await MainActor.run {
                    self.showAlert(
                        title: "Lexi proxy is offline",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    @objc private func copyLastAnswer() {
        guard let lastAnswer, !lastAnswer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastAnswer, forType: .string)
    }

    @objc private func quitLexi() {
        NSApp.terminate(nil)
    }

    func setupGlobalHotkey() {
        print("Setting up hold-based Option+Space global hotkey...")
        hotkeyManager.registerOptionSpace(
            onPressed: { [weak self] in
                self?.beginLookupHotkeyHold()
            },
            onReleased: { [weak self] in
                self?.finishLookupHotkeyHold()
            }
        )
        print("Option+Space hold-to-select explain-term hotkey registered")
    }

    private func setupBuddyCapture() {
        let coordinator = BuddyCaptureCoordinator()
        coordinator.isEnabledProvider = { [weak self] in
            self?.isEnabled == true
        }
        coordinator.onCaptureReady = { [weak self] capture in
            self?.cursorBuddy.setActivity(.working)
            self?.requestBuddyExplanation(for: capture)
        }
        coordinator.onCaptureCancelled = { [weak self] in
            self?.cursorBuddy.setActivity(.idle)
        }
        coordinator.onPermissionsMissing = { [weak self] permissions in
            guard let self else { return }
            self.cursorBuddy.pulse(.error)
            self.showPermissionOnboarding()
            self.rawCapturePanel.show(status: .buddyPermissionMissing(permissions), anchorRect: nil)
        }
        coordinator.onMessage = { [weak self] title, message in
            self?.rawCapturePanel.show(status: .buddyMessage(title: title, message: message), anchorRect: nil)
        }
        coordinator.onActivityChanged = { [weak self] activity in
            self?.cursorBuddy.setActivity(activity)
        }
        coordinator.onCursorHint = { [weak self] text, duration in
            self?.cursorBuddy.showHint(text, duration: duration)
        }
        coordinator.contextualKeytermsProvider = { [weak self] in
            guard let self else { return [] }
            return self.sessionMemory.keyterms(extraText: [self.rawCapturePanel.currentAnswer ?? ""])
        }
        coordinator.onError = { [weak self] message in
            self?.cursorBuddy.pulse(.error)
            self?.rawCapturePanel.show(status: .buddyError(nil, message), anchorRect: nil)
        }
        coordinator.onInstallFailed = { [weak self] in
            guard let self else { return }
            self.cursorBuddy.pulse(.error)
            self.showPermissionOnboarding()
            self.rawCapturePanel.show(status: .buddyPermissionMissing([.accessibility]), anchorRect: nil)
        }
        coordinator.start()
        buddyCoordinator = coordinator
        print("Option+Command hold-to-capture monitor registered")
    }

    private func beginLookupHotkeyHold() {
        guard isEnabled, !isLookupHotkeyHeld else { return }
        isLookupHotkeyHeld = true
        cursorBuddy.setActivity(.listening)
        startHighlightVoiceCaptureIfAvailable()
    }

    private func finishLookupHotkeyHold() {
        guard isLookupHotkeyHeld else { return }
        isLookupHotkeyHeld = false
        let hotkeyStartedAt = currentMilliseconds()
        guard isHighlightVoiceCaptureArmed else {
            finishLookupHotkeyHold(spokenQuestion: "", hotkeyStartedAt: hotkeyStartedAt)
            return
        }
        isHighlightVoiceCaptureArmed = false
        Task { @MainActor in
            let spokenQuestion = await highlightVoiceCapture.stop()
            finishLookupHotkeyHold(spokenQuestion: spokenQuestion, hotkeyStartedAt: hotkeyStartedAt)
        }
    }

    private func finishLookupHotkeyHold(spokenQuestion: String, hotkeyStartedAt: Double) {
        guard isEnabled else {
            cursorBuddy.setActivity(.idle)
            return
        }

        if rawCapturePanel.isVisible {
            let selectedText = rawCapturePanel.selectedAnswerText
            print("Panel visible, selected text: \(selectedText ?? "nil")")
            if let selectedText,
               rawCapturePanel.requestNestedLookup(term: selectedText) {
                lastAnswer = rawCapturePanel.currentAnswer
                rebuildMenu()
                print("Nested lookup requested for: \(selectedText)")
            } else {
                cursorBuddy.setActivity(.idle)
                print("Option+Space released without a nested selection; cancelling lookup")
            }
            return
        }

        let captureStartedAt = currentMilliseconds()
        switch selectionCapture.capture() {
        case .success(let capture):
            let captureWithQuestion = capture.withQuestion(spokenQuestion)
            cursorBuddy.setActivity(.working)
            let captureMs = Int(currentMilliseconds() - captureStartedAt)
            print("Capture success: term='\(captureWithQuestion.term)', passageLength=\(captureWithQuestion.passage.count), app='\(captureWithQuestion.appName)', source=\(captureWithQuestion.source), capture=\(captureMs)ms")
            rawCapturePanel.show(status: .loading(captureWithQuestion), anchorRect: captureWithQuestion.anchorRect)
            let panelShownMs = Int(currentMilliseconds() - hotkeyStartedAt)
            print("Lexi latency: panelShown=\(panelShownMs)ms")
            requestExplanation(for: captureWithQuestion, hotkeyStartedAt: hotkeyStartedAt)
        case .noSelection(let appName, let windowTitle):
            print("Option+Space released without selected text: app='\(appName)', window='\(windowTitle)'")
            cursorBuddy.setActivity(.idle)
        case .accessibilityPermissionMissing:
            print("Capture failed: Accessibility permission missing")
            cursorBuddy.pulse(.error)
            showPermissionOnboarding()
            rawCapturePanel.show(status: .noPermission, anchorRect: nil)
        }
    }

    private func startHighlightVoiceCaptureIfAvailable() {
        isHighlightVoiceCaptureArmed = false
        guard BuddyPermissions.status(.microphone).isGranted,
              AppConfiguration.voiceProvider == .assemblyAI || BuddyPermissions.status(.speechRecognition).isGranted else {
            highlightVoiceCapture.cancel()
            return
        }
        do {
            try highlightVoiceCapture.start(keyterms: sessionMemory.keyterms(extraText: [rawCapturePanel.currentAnswer ?? ""])) { _ in }
            isHighlightVoiceCaptureArmed = true
        } catch {
            highlightVoiceCapture.cancel()
        }
    }

    private func requestBuddyExplanation(for capture: BuddyCaptureContext) {
        explainTask?.cancel()
        cursorBuddy.setActivity(.working)
        rawCapturePanel.show(status: .buddyLoading(capture), anchorRect: capture.anchorRect)

        explainTask = Task { [weak self] in
            guard let self else { return }
            var didLogFirstToken = false

            do {
                let requestStartedAt = currentMilliseconds()
                let client = ExplainClient()
                let answer = try await client.explainBuddy(
                    imageBase64: capture.screenshot?.base64Data,
                    imageMediaType: capture.screenshot?.mediaType ?? RegionScreenshotCapture.mediaType,
                    question: capture.question,
                    appName: capture.appName,
                    windowTitle: capture.windowTitle,
                    ocrText: capture.screenshot?.recognizedText ?? "",
                    sessionContext: self.sessionMemory.contextSummary,
                    onDelta: { [weak self] _, accumulated in
                        guard let self else { return }
                        if !didLogFirstToken {
                            didLogFirstToken = true
                            let networkTtftMs = Int(self.currentMilliseconds() - requestStartedAt)
                            print("Lexi Buddy Capture latency: firstVisibleToken=\(networkTtftMs)ms")
                        }
                        self.cursorBuddy.setActivity(.streaming)
                        self.rawCapturePanel.update(status: .buddyStreaming(capture, accumulated))
                    },
                    onTiming: { timing in
                        if let proxyTtftMs = timing.proxyTtftMs, let anthropicTtftMs = timing.anthropicTtftMs {
                            print("Lexi Buddy proxy timing: proxyTtft=\(proxyTtftMs)ms anthropicTtft=\(anthropicTtftMs)ms")
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                let callout = BuddyCalloutParser.parse(answer)
                await MainActor.run {
                    let finalAnswer = callout.answer.isEmpty ? answer : callout.answer
                    let stack = LookupNavigationStack(
                        rootTerm: capture.displayTitle,
                        sourceText: capture.sourceText,
                        answer: finalAnswer,
                        appName: capture.appName,
                        windowTitle: capture.windowTitle,
                        sourceLabel: capture.modeLabel
                    )
                    self.lastAnswer = finalAnswer
                    self.sessionMemory.record(prompt: capture.displayTitle, answer: finalAnswer, source: capture.modeLabel)
                    self.rawCapturePanel.update(status: .lookup(stack))
                    self.showBuddyCalloutIfAvailable(callout, capture: capture)
                    self.speakIfEnabled(finalAnswer)
                    self.cursorBuddy.setActivity(.idle)
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription.isEmpty ? "Couldn't explain that Buddy Capture — try again." : error.localizedDescription
                await MainActor.run {
                    self.cursorBuddy.pulse(.error)
                    self.rawCapturePanel.update(status: .buddyError(capture, message))
                }
            }
        }
    }

    private func requestNestedExplanation(term: String, stack parentStack: LookupNavigationStack) {
        explainTask?.cancel()
        cursorBuddy.setActivity(.working)
        guard let childId = rawCapturePanel.beginNestedLookup(term: term) else {
            cursorBuddy.setActivity(.idle)
            return
        }
        lastAnswer = rawCapturePanel.currentAnswer
        rebuildMenu()

        explainTask = Task { [weak self] in
            guard let self else { return }
            do {
                let requestStartedAt = currentMilliseconds()
                let client = ExplainClient()
                let answer = try await client.explainNested(term: term, in: parentStack, sessionContext: self.sessionMemory.contextSummary) { [weak self] _, accumulated in
                    guard let self else { return }
                    self.cursorBuddy.setActivity(.streaming)
                    self.rawCapturePanel.updateLookupAnswer(nodeId: childId, answer: accumulated)
                } onTiming: { timing in
                    if let proxyTtftMs = timing.proxyTtftMs, let anthropicTtftMs = timing.anthropicTtftMs {
                        print("Lexi nested timing: proxyTtft=\(proxyTtftMs)ms anthropicTtft=\(anthropicTtftMs)ms totalStarted=\(Int(self.currentMilliseconds() - requestStartedAt))ms")
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.rawCapturePanel.updateLookupAnswer(nodeId: childId, answer: answer)
                    self.lastAnswer = answer
                    self.sessionMemory.record(prompt: term, answer: answer, source: "Nested lookup")
                    self.speakIfEnabled(answer)
                    self.cursorBuddy.setActivity(.idle)
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription.isEmpty ? "Couldn't explain that nested term — try again." : error.localizedDescription
                await MainActor.run {
                    self.cursorBuddy.pulse(.error)
                    self.rawCapturePanel.updateLookupAnswer(nodeId: childId, answer: message)
                    self.lastAnswer = message
                    self.rebuildMenu()
                }
            }
        }
    }

    private func requestFollowUp(question: String, stack parentStack: LookupNavigationStack) {
        explainTask?.cancel()
        cursorBuddy.setActivity(.working)
        guard let childId = rawCapturePanel.beginFollowUp(question: question) else {
            cursorBuddy.setActivity(.idle)
            return
        }
        lastAnswer = rawCapturePanel.currentAnswer
        rebuildMenu()

        explainTask = Task { [weak self] in
            guard let self else { return }
            do {
                let requestStartedAt = currentMilliseconds()
                let client = ExplainClient()
                let answer = try await client.explainFollowUp(question: question, in: parentStack, sessionContext: self.sessionMemory.contextSummary) { [weak self] _, accumulated in
                    guard let self else { return }
                    self.cursorBuddy.setActivity(.streaming)
                    self.rawCapturePanel.updateLookupAnswer(nodeId: childId, answer: accumulated)
                } onTiming: { timing in
                    if let proxyTtftMs = timing.proxyTtftMs, let anthropicTtftMs = timing.anthropicTtftMs {
                        print("Lexi follow-up timing: proxyTtft=\(proxyTtftMs)ms anthropicTtft=\(anthropicTtftMs)ms totalStarted=\(Int(self.currentMilliseconds() - requestStartedAt))ms")
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.rawCapturePanel.updateLookupAnswer(nodeId: childId, answer: answer)
                    self.lastAnswer = answer
                    self.sessionMemory.record(prompt: question, answer: answer, source: "Follow-up")
                    self.speakIfEnabled(answer)
                    self.cursorBuddy.setActivity(.idle)
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription.isEmpty ? "Couldn't answer that follow-up — try again." : error.localizedDescription
                await MainActor.run {
                    self.cursorBuddy.pulse(.error)
                    self.rawCapturePanel.updateLookupAnswer(nodeId: childId, answer: message)
                    self.lastAnswer = message
                    self.rebuildMenu()
                }
            }
        }
    }

    private func requestExplanation(for capture: CapturedSelection, hotkeyStartedAt: Double) {
        explainTask?.cancel()
        explainTask = Task { [weak self] in
            guard let self else { return }
            var didLogFirstToken = false

            do {
                let requestStartedAt = currentMilliseconds()
                let client = ExplainClient()
                let answer = try await client.explain(capture, sessionContext: self.sessionMemory.contextSummary) { [weak self] _, accumulated in
                    guard let self else { return }
                    if !didLogFirstToken {
                        didLogFirstToken = true
                        let appTtftMs = Int(self.currentMilliseconds() - hotkeyStartedAt)
                        let networkTtftMs = Int(self.currentMilliseconds() - requestStartedAt)
                        print("Lexi latency: firstVisibleToken=\(appTtftMs)ms networkAndModel=\(networkTtftMs)ms")
                    }
                    self.cursorBuddy.setActivity(.streaming)
                    self.rawCapturePanel.update(status: .streaming(capture, accumulated))
                } onTiming: { timing in
                    if let proxyTtftMs = timing.proxyTtftMs, let anthropicTtftMs = timing.anthropicTtftMs {
                        print("Lexi proxy timing: proxyTtft=\(proxyTtftMs)ms anthropicTtft=\(anthropicTtftMs)ms")
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let stack = LookupNavigationStack(
                        rootTerm: capture.term,
                        sourceText: capture.passage,
                        answer: answer,
                        appName: capture.appName,
                        windowTitle: capture.windowTitle,
                        sourceLabel: capture.source == .accessibility ? "Accessibility API" : "Clipboard fallback"
                    )
                    self.lastAnswer = answer
                    self.sessionMemory.record(prompt: capture.term, answer: answer, source: "Highlight")
                    self.rawCapturePanel.update(status: .lookup(stack))
                    self.speakIfEnabled(answer)
                    self.cursorBuddy.setActivity(.idle)
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription.isEmpty ? "Couldn't reach the assistant — try again." : error.localizedDescription
                await MainActor.run {
                    self.cursorBuddy.pulse(.error)
                    self.rawCapturePanel.update(status: .error(capture, message))
                }
            }
        }
    }

    private func speakIfEnabled(_ answer: String) {
        guard AppConfiguration.current.isReadAloudEnabled else { return }
        ttsClient.stop()
        Task { @MainActor in
            do {
                try await self.ttsClient.speak(answer)
            } catch {
                print("Lexi read-aloud failed: \(error.localizedDescription)")
            }
        }
    }

    private func showBuddyCalloutIfAvailable(_ callout: BuddyCalloutParseResult, capture: BuddyCaptureContext) {
        guard let point = callout.point,
              let screenshot = capture.screenshot,
              let anchorRect = capture.anchorRect else { return }
        let clampedX = max(0, min(point.x, CGFloat(screenshot.pixelWidth)))
        let clampedY = max(0, min(point.y, CGFloat(screenshot.pixelHeight)))
        let xRatio = anchorRect.width / CGFloat(max(1, screenshot.pixelWidth))
        let yRatio = anchorRect.height / CGFloat(max(1, screenshot.pixelHeight))
        let screenPoint = CGPoint(
            x: anchorRect.minX + clampedX * xRatio,
            y: anchorRect.maxY - clampedY * yRatio
        )
        calloutOverlay.show(point: screenPoint, label: callout.label)
    }

    private func showAlert(title: String, message: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        if let message {
            alert.informativeText = message
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func currentMilliseconds() -> Double {
        Date().timeIntervalSince1970 * 1000
    }
}
