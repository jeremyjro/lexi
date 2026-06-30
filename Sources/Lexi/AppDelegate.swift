import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let firstRunDefaultsKey = "LexiHasCompletedFirstRun"
    private var statusItem: NSStatusItem?
    private let homePopover = NSPopover()
    private let hotkeyManager = HotkeyManager()
    private let selectionCapture = SelectionCapture()
    private let rawCapturePanel = RawCapturePanelController()
    private let sessionMemory = ResearchSessionMemory()
    private let contextSampler = LexiContextSampler()
    private let activeTextContextCapture = ActiveTextContextCapture()
    private let ttsClient = ElevenLabsTTSClient()
    private let highlightVoiceCapture = BuddyVoiceCapture()
    private let calloutOverlay = BuddyCalloutOverlayController()
    private let cursorBuddy = BuddyCursorFollowerController()
    private var buddyCoordinator: BuddyCaptureCoordinator?
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?
    private var homeWindow: NSWindow?
    private var explainTask: Task<Void, Never>?
    private var lastAnswer: String?
    private var isLookupHotkeyHeld = false
    private var lookupHotkeyStartedAt: Double = 0
    private var isHighlightVoiceCaptureArmed = false
    private var isEnabled = true
    private var hasCompletedFirstRun: Bool {
        get { UserDefaults.standard.bool(forKey: Self.firstRunDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.firstRunDefaultsKey) }
    }

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
        contextSampler.start()
        BuddyTranscriptionProviderFactory.prewarmIfNeeded()

        requestAccessibilityPermission()
        let isTrusted = AXIsProcessTrusted()
        print("Accessibility trusted: \(isTrusted)")

        if !isTrusted {
            print("Accessibility permission is not enabled")
        }

        setupGlobalHotkey()
        presentFirstRunIfNeeded()
        print("Lexi started successfully")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHomePopover(forceShow: true)
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""
        item.button?.image = LexiBrand.statusItemImage()
        item.button?.image?.accessibilityDescription = "Lexi"
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        rebuildMenu()
    }

    @discardableResult
    private func rebuildMenu() -> NSMenu {
        buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let welcomeItem = NSMenuItem(title: "Welcome to Lexi…", action: #selector(showWelcome), keyEquivalent: "")
        welcomeItem.target = self
        menu.addItem(welcomeItem)

        menu.addItem(.separator())

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

        return menu
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func presentFirstRunIfNeeded() {
        guard !hasCompletedFirstRun else { return }
        showWelcome()
    }

    @objc private func showWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = WelcomeWindowController { [weak self] in
                self?.hasCompletedFirstRun = true
                self?.welcomeWindow = nil
            }
        }
        welcomeWindow?.showWindow(nil)
        welcomeWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showHomePopover(forceShow: Bool = false) {
        guard let button = statusItem?.button else {
            showHomeWindow()
            return
        }

        homePopover.behavior = .transient
        homePopover.contentViewController = makeHomeContentController()
        homePopover.contentSize = NSSize(width: 320, height: 420)

        if homePopover.isShown {
            if forceShow {
                NSApp.activate(ignoringOtherApps: true)
            } else {
                homePopover.close()
            }
            return
        }

        homePopover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showHomeWindow() {
        if homeWindow == nil {
            homeWindow = makeHomeWindow()
        }
        homeWindow?.contentViewController = makeHomeContentController()
        homeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeHomeContentController() -> NSHostingController<HomeView> {
        NSHostingController(
            rootView: HomeView(
                isEnabled: isEnabled,
                onStartBuddy: { [weak self] in
                    self?.startBuddyCapture()
                },
                onToggleEnabled: { [weak self] in
                    self?.toggleEnabled()
                },
                onShowWelcome: { [weak self] in
                    self?.showWelcome()
                },
                onOpenSettings: { [weak self] in
                    self?.showSettings()
                },
                onQuit: { [weak self] in
                    self?.quitLexi()
                }
            )
        )
    }

    private func makeHomeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: makeHomeContentController())
        window.title = "Lexi"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 320, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .lexiPaper
        return window
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true

        if isSecondaryClick {
            statusItem?.menu = buildMenu()
            button.performClick(nil)
            statusItem?.menu = nil
        } else {
            showHomePopover()
        }
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
        if homePopover.isShown {
            homePopover.contentViewController = makeHomeContentController()
        }
        if homeWindow != nil {
            homeWindow?.contentViewController = makeHomeContentController()
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
            showSettings()
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
                    let assemblyTimeout = health.assemblyAITokenTimeoutMs.map { "\($0)ms" } ?? "Unknown"
                    let elevenLabsStatus = health.elevenLabsConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                    let perplexityStatus = health.perplexityConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                    self.showAlert(
                        title: health.ok ? "Lexi proxy is online" : "Lexi proxy responded unexpectedly",
                        message: "URL: \(client.baseURLDescription)\nModel: \(health.model)\nVision model: \(health.visionModel ?? health.model)\nLocal token configured: \(client.hasProxyToken ? "Yes" : "No")\nBackend key configured: \(backendKeyStatus)\nBackend token configured: \(backendTokenStatus)\nAssemblyAI configured: \(assemblyStatus)\nAssemblyAI token timeout: \(assemblyTimeout)\nVoice buffer: \(AppConfiguration.voiceAudioBufferSizeFrames) frames\nAssemblyAI final fallback: \(String(format: "%.1f", AppConfiguration.assemblyAIFinalTranscriptFallbackDelaySeconds))s\nElevenLabs configured: \(elevenLabsStatus)\nPerplexity configured: \(perplexityStatus)\nResearch provider: \(health.researchProvider ?? "none")\nResearch mode: \(health.researchMode ?? "unknown")\nResearch model: \(health.perplexityModel ?? "unknown")"
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
            self.showSettings()
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
            self.showSettings()
            self.rawCapturePanel.show(status: .buddyPermissionMissing([.accessibility]), anchorRect: nil)
        }
        coordinator.start()
        buddyCoordinator = coordinator
        print("Option+Command hold-to-capture monitor registered")
    }

    private func beginLookupHotkeyHold() {
        guard isEnabled, !isLookupHotkeyHeld else { return }
        isLookupHotkeyHeld = true
        lookupHotkeyStartedAt = currentMilliseconds()
        cursorBuddy.setActivity(.listening)
        startHighlightVoiceCaptureIfAvailable()
    }

    private func finishLookupHotkeyHold() {
        guard isLookupHotkeyHeld else { return }
        isLookupHotkeyHeld = false
        let hotkeyStartedAt = lookupHotkeyStartedAt > 0 ? lookupHotkeyStartedAt : currentMilliseconds()
        lookupHotkeyStartedAt = 0
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
            let captureMs = Int(currentMilliseconds() - captureStartedAt)
            print("Capture success: term='\(captureWithQuestion.term)', passageLength=\(captureWithQuestion.passage.count), app='\(captureWithQuestion.appName)', source=\(captureWithQuestion.source), capture=\(captureMs)ms")
            if CompositionIntentDetector.isWholeDeletionInstruction(spokenQuestion) {
                if let compositionContext = activeTextContextCapture.capture(selectedText: captureWithQuestion.term, surroundingText: captureWithQuestion.passage),
                   compositionContext.isWritable {
                    requestDeletion(instruction: spokenQuestion, context: compositionContext)
                } else {
                    cursorBuddy.setActivity(.idle)
                    cursorBuddy.showHint("Click into a text field first", duration: 2.0)
                }
                return
            }
            if CompositionIntentDetector.isCompositionInstruction(spokenQuestion) {
                if let compositionContext = activeTextContextCapture.capture(selectedText: captureWithQuestion.term, surroundingText: captureWithQuestion.passage),
                   compositionContext.isWritable {
                    requestComposition(instruction: spokenQuestion, context: compositionContext)
                } else {
                    cursorBuddy.setActivity(.idle)
                    cursorBuddy.showHint("Click into a text field first", duration: 2.0)
                }
                return
            }
            cursorBuddy.setActivity(.working)
            rawCapturePanel.show(status: .loading(captureWithQuestion), anchorRect: captureWithQuestion.anchorRect)
            let panelShownMs = Int(currentMilliseconds() - hotkeyStartedAt)
            print("Lexi latency: panelShown=\(panelShownMs)ms")
            requestExplanation(for: captureWithQuestion, hotkeyStartedAt: hotkeyStartedAt)
        case .noSelection(let appName, let windowTitle):
            let trimmedQuestion = spokenQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            print("Option+Space released without selected text: app='\(appName)', window='\(windowTitle)'")
            guard !trimmedQuestion.isEmpty else {
                cursorBuddy.setActivity(.idle)
                return
            }
            if CompositionIntentDetector.isWholeDeletionInstruction(trimmedQuestion) {
                if let compositionContext = activeTextContextCapture.capture(),
                   compositionContext.isWritable,
                   !compositionContext.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    requestDeletion(instruction: trimmedQuestion, context: compositionContext)
                } else {
                    cursorBuddy.setActivity(.idle)
                    cursorBuddy.showHint("Select text to delete", duration: 2.0)
                }
            } else if CompositionIntentDetector.isCompositionInstruction(trimmedQuestion) {
                if let compositionContext = activeTextContextCapture.capture(),
                   compositionContext.isWritable {
                    requestComposition(instruction: trimmedQuestion, context: compositionContext)
                } else {
                    cursorBuddy.setActivity(.idle)
                    cursorBuddy.showHint("Click into a text field first", duration: 2.0)
                }
            } else {
                requestFocusedScreenAnswer(question: trimmedQuestion, fallbackAppName: appName, fallbackWindowTitle: windowTitle)
            }
        case .accessibilityPermissionMissing:
            print("Capture failed: Accessibility permission missing")
            cursorBuddy.pulse(.error)
            showSettings()
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

    private func requestDeletion(instruction: String, context: ActiveTextCompositionContext) {
        explainTask?.cancel()
        cursorBuddy.setActivity(.working)
        cursorBuddy.showHint("Deleting selection…", duration: 1.2)
        let selectedText = context.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else {
            cursorBuddy.setActivity(.idle)
            cursorBuddy.showHint("Select text to delete", duration: 2.0)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let didDelete = await StreamingTextInserter().replaceSelection(with: "", allowKeyboardFallback: true)
            await MainActor.run {
                if didDelete {
                    self.sessionMemory.record(prompt: instruction, answer: "Deleted selected text", source: "Active deletion")
                    self.cursorBuddy.setActivity(.idle)
                    self.cursorBuddy.showHint("Deleted selection", duration: 1.5)
                } else {
                    self.cursorBuddy.pulse(.error)
                    self.cursorBuddy.showHint("Couldn’t delete there", duration: 2.0)
                }
            }
        }
    }

    private func requestFocusedScreenAnswer(question: String, fallbackAppName: String, fallbackWindowTitle: String) {
        explainTask?.cancel()
        cursorBuddy.setActivity(.working)
        cursorBuddy.showHint("Reading current screen…", duration: 1.5)
        Task { [weak self] in
            guard let self else { return }
            let activeContext = self.activeTextContextCapture.capture()
            let appName = activeContext?.appName.isEmpty == false ? activeContext?.appName ?? fallbackAppName : fallbackAppName
            let windowTitle = activeContext?.windowTitle.isEmpty == false ? activeContext?.windowTitle ?? fallbackWindowTitle : fallbackWindowTitle
            var screenshot: RegionScreenshot?
            do {
                if let focusedWindow = try await RegionScreenshotCapture.captureFocusedWindow() {
                    screenshot = focusedWindow
                } else {
                    screenshot = try await RegionScreenshotCapture.captureCursorScreen()
                }
            } catch {
                print("Lexi current-screen answer capture failed: \(error.localizedDescription)")
            }
            let textContext = [activeContext?.selectedText, activeContext?.surroundingText, activeContext?.currentText]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            await MainActor.run {
                guard screenshot != nil || !textContext.isEmpty else {
                    self.cursorBuddy.pulse(.error)
                    self.cursorBuddy.showHint("Couldn’t read current screen", duration: 2.0)
                    return
                }
                self.requestBuddyExplanation(for: BuddyCaptureContext(
                    question: question,
                    screenshot: screenshot,
                    appName: appName.isEmpty ? "Unknown" : appName,
                    windowTitle: windowTitle,
                    anchorRect: screenshot?.sourceRect,
                    modeLabel: "Current screen",
                    textContext: textContext
                ))
            }
        }
    }

    private func visibleScreenTextContext() async -> String {
        do {
            var screenshot = try await RegionScreenshotCapture.captureFocusedWindow()
            if screenshot == nil {
                screenshot = try await RegionScreenshotCapture.captureCursorScreen()
            }
            let text = screenshot?.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "" : "VISIBLE SCREEN OCR:\n\(text)"
        } catch {
            return ""
        }
    }

    private func requestComposition(instruction: String, context: ActiveTextCompositionContext) {
        explainTask?.cancel()
        cursorBuddy.setActivity(.working)

        // Write-back strategy depends on whether the user highlighted text:
        // - Selection present  → transform/replace it in ONE shot once the full
        //   answer arrives (no streaming). Streaming a replacement token-by-token
        //   into editors like Google Docs duplicates/drops text, fragments undo,
        //   and races the clipboard restore.
        // - No selection       → insert new text at the caret, streamed live so the
        //   user sees it appear as it is generated.
        let replaceMode = context.hasSelection
        let inserter = StreamingTextInserter()
        if replaceMode {
            cursorBuddy.showHint("Rewriting selection in \(context.appName)…", duration: 2.0)
        } else {
            cursorBuddy.showHint("Composing into \(context.appName)…", duration: 2.0)
            inserter.begin()
        }

        explainTask = Task { [weak self] in
            guard let self else { return }
            do {
                let requestStartedAt = currentMilliseconds()
                let client = ExplainClient()
                let visibleScreenText = await self.visibleScreenTextContext()
                let answer = try await client.compose(
                    instruction: instruction,
                    context: context,
                    sessionContext: self.inferenceContext(for: [instruction, context.selectedText, context.surroundingText, context.currentText, visibleScreenText]),
                    onDelta: { [weak self] delta, _ in
                        guard let self else { return }
                        self.cursorBuddy.setActivity(.streaming)
                        if !replaceMode {
                            inserter.insert(delta)
                        }
                    },
                    onTiming: { timing in
                        if let proxyTtftMs = timing.proxyTtftMs, let anthropicTtftMs = timing.anthropicTtftMs {
                            print("Lexi compose timing: proxyTtft=\(proxyTtftMs)ms anthropicTtft=\(anthropicTtftMs)ms totalStarted=\(Int(self.currentMilliseconds() - requestStartedAt))ms")
                        }
                    }
                )
                if Task.isCancelled {
                    await MainActor.run {
                        inserter.cancel()
                        self.cursorBuddy.setActivity(.idle)
                    }
                    return
                }

                if replaceMode {
                    let replacement = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    let didReplace = !replacement.isEmpty
                        && (await inserter.replaceSelection(with: replacement, allowKeyboardFallback: true))
                    await MainActor.run {
                        if didReplace {
                            self.recordComposition(instruction: instruction, answer: answer, context: context)
                            self.cursorBuddy.setActivity(.idle)
                            self.cursorBuddy.showHint("Updated selection", duration: 1.5)
                            self.rebuildMenu()
                        } else {
                            self.cursorBuddy.pulse(.error)
                            self.cursorBuddy.showHint("Couldn’t update that selection", duration: 2.0)
                        }
                    }
                    return
                }

                await MainActor.run {
                    inserter.finish()
                    self.recordComposition(instruction: instruction, answer: answer, context: context)
                    self.cursorBuddy.setActivity(.idle)
                    self.cursorBuddy.showHint("Inserted draft", duration: 1.5)
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    inserter.cancel()
                    self.cursorBuddy.pulse(.error)
                    self.cursorBuddy.showHint("Couldn’t compose there", duration: 2.0)
                    print("Lexi composition failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func recordComposition(instruction: String, answer: String, context: ActiveTextCompositionContext) {
        lastAnswer = answer
        sessionMemory.record(prompt: instruction, answer: answer, source: "Active composition")
        LexiInteractionEventStore.shared.record(
            prompt: instruction,
            answer: answer,
            source: "Active composition",
            appName: context.appName,
            windowTitle: context.windowTitle
        )
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
                let visibleText = [capture.screenshot?.recognizedText, capture.textContext]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let answer = try await client.explainBuddy(
                    imageBase64: capture.screenshot?.base64Data,
                    imageMediaType: capture.screenshot?.mediaType ?? RegionScreenshotCapture.mediaType,
                    question: capture.question,
                    appName: capture.appName,
                    windowTitle: capture.windowTitle,
                    ocrText: visibleText,
                    sessionContext: self.inferenceContext(for: [capture.displayTitle, capture.question, capture.sourceText, visibleText]),
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
                    LexiInteractionEventStore.shared.record(
                        prompt: capture.displayTitle,
                        answer: finalAnswer,
                        source: capture.modeLabel,
                        appName: capture.appName,
                        windowTitle: capture.windowTitle
                    )
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
                let answer = try await client.explainNested(term: term, in: parentStack, sessionContext: self.inferenceContext(for: [term, parentStack.currentNode?.answer ?? "", parentStack.rootNode?.sourceText ?? ""])) { [weak self] _, accumulated in
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
                    LexiInteractionEventStore.shared.record(
                        prompt: term,
                        answer: answer,
                        source: "Nested lookup",
                        appName: "Lexi",
                        windowTitle: parentStack.currentNode?.term ?? parentStack.rootNode?.term ?? ""
                    )
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
                let answer = try await client.explainFollowUp(question: question, in: parentStack, sessionContext: self.inferenceContext(for: [question, parentStack.currentNode?.answer ?? "", parentStack.rootNode?.sourceText ?? ""])) { [weak self] _, accumulated in
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
                    LexiInteractionEventStore.shared.record(
                        prompt: question,
                        answer: answer,
                        source: "Follow-up",
                        appName: parentStack.currentNode?.appName ?? "Lexi",
                        windowTitle: parentStack.currentNode?.windowTitle ?? parentStack.rootNode?.term ?? ""
                    )
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
                let answer = try await client.explain(capture, sessionContext: self.inferenceContext(for: [capture.term, capture.passage, capture.question ?? ""])) { [weak self] _, accumulated in
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
                    LexiInteractionEventStore.shared.record(
                        prompt: capture.term,
                        answer: answer,
                        source: "Highlight",
                        appName: capture.appName,
                        windowTitle: capture.windowTitle
                    )
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

    private func inferenceContext(for texts: [String]) -> String {
        let query = texts.joined(separator: "\n")
        let persistentContext = LexiInteractionEventStore.shared.relevantContextSummary(for: query)
        return [sessionMemory.contextSummary, persistentContext]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
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
