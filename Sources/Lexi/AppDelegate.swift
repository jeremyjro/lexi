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
    private var buddyCoordinator: BuddyCaptureCoordinator?
    private var settingsWindow: SettingsWindowController?
    private var explainTask: Task<Void, Never>?
    private var lastAnswer: String?
    private var isEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        rawCapturePanel.onDismiss = { [weak self] in
            self?.explainTask?.cancel()
        }
        rawCapturePanel.onNestedLookupRequested = { [weak self] term, stack in
            self?.requestNestedExplanation(term: term, stack: stack)
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
            explainTask?.cancel()
            buddyCoordinator?.cancelActiveCapture()
            rawCapturePanel.hide()
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
            message: "Hold Option + Space, then release to explain highlighted text. Hold Option + Command, then release to enter Buddy Capture; drag a screen region, and releasing the trackpad/mouse sends the screenshot and spoken question. Inside a Lexi answer, highlight a word or phrase, then use → to drill down or reopen the latest child. Use ← to pop up and Esc to close."
        )
    }

    func startBuddyCapture() {
        guard let buddyCoordinator else {
            rawCapturePanel.show(status: .buddyError(nil, "Buddy Capture is not initialized. Quit and reopen Lexi."), anchorRect: nil)
            return
        }
        rawCapturePanel.show(
            status: .buddyMessage(
                title: "Buddy Capture starting",
                message: "A full-screen capture overlay should appear now. Drag a region and release to submit."
            ),
            anchorRect: nil
        )
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
                    self.showAlert(
                        title: health.ok ? "Lexi proxy is online" : "Lexi proxy responded unexpectedly",
                        message: "URL: \(client.baseURLDescription)\nModel: \(health.model)\nVision model: \(health.visionModel ?? health.model)\nLocal token configured: \(client.hasProxyToken ? "Yes" : "No")\nBackend key configured: \(backendKeyStatus)\nBackend token configured: \(backendTokenStatus)"
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
        print("Setting up Option+Space global hotkey...")
        hotkeyManager.registerOptionSpace { [weak self] in
            self?.handleLookupHotkey()
        }
        print("Option+Space explain-term release hotkey registered")
    }

    private func setupBuddyCapture() {
        let coordinator = BuddyCaptureCoordinator()
        coordinator.isEnabledProvider = { [weak self] in
            self?.isEnabled == true
        }
        coordinator.onCaptureReady = { [weak self] capture in
            self?.requestBuddyExplanation(for: capture)
        }
        coordinator.onPermissionsMissing = { [weak self] permissions in
            guard let self else { return }
            self.showPermissionOnboarding()
            self.rawCapturePanel.show(status: .buddyPermissionMissing(permissions), anchorRect: nil)
        }
        coordinator.onError = { [weak self] message in
            self?.rawCapturePanel.show(status: .buddyError(nil, message), anchorRect: nil)
        }
        coordinator.onInstallFailed = { [weak self] in
            guard let self else { return }
            self.showPermissionOnboarding()
            self.rawCapturePanel.show(status: .buddyPermissionMissing([.accessibility]), anchorRect: nil)
        }
        coordinator.start()
        buddyCoordinator = coordinator
        print("Option+Command Buddy Capture release monitor registered")
    }

    private func handleLookupHotkey() {
        let hotkeyStartedAt = currentMilliseconds()
        guard isEnabled else { return }

        if rawCapturePanel.isVisible {
            let selectedText = rawCapturePanel.selectedAnswerText
            print("Panel visible, selected text: \(selectedText ?? "nil")")
            if let selectedText,
               rawCapturePanel.requestNestedLookup(term: selectedText) {
                lastAnswer = rawCapturePanel.currentAnswer
                rebuildMenu()
                print("Nested lookup requested for: \(selectedText)")
            } else {
                explainTask?.cancel()
                rawCapturePanel.hide()
                print("No selection or request failed, hiding panel")
            }
            return
        }

        let captureStartedAt = currentMilliseconds()
        switch selectionCapture.capture() {
        case .success(let capture):
            let captureMs = Int(currentMilliseconds() - captureStartedAt)
            print("Capture success: term='\(capture.term)', passageLength=\(capture.passage.count), app='\(capture.appName)', source=\(capture.source), capture=\(captureMs)ms")
            rawCapturePanel.show(status: .loading(capture), anchorRect: capture.anchorRect)
            let panelShownMs = Int(currentMilliseconds() - hotkeyStartedAt)
            print("Lexi latency: panelShown=\(panelShownMs)ms")
            requestExplanation(for: capture, hotkeyStartedAt: hotkeyStartedAt)
        case .noSelection(let appName, let windowTitle):
            print("Capture returned no selection: app='\(appName)', window='\(windowTitle)'")
            rawCapturePanel.show(status: .noSelection(appName: appName, windowTitle: windowTitle), anchorRect: nil)
        case .accessibilityPermissionMissing:
            print("Capture failed: Accessibility permission missing")
            showPermissionOnboarding()
            rawCapturePanel.show(status: .noPermission, anchorRect: nil)
        }
    }

    private func requestBuddyExplanation(for capture: BuddyCaptureContext) {
        explainTask?.cancel()
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
                    onDelta: { [weak self] _, accumulated in
                        guard let self else { return }
                        if !didLogFirstToken {
                            didLogFirstToken = true
                            let networkTtftMs = Int(self.currentMilliseconds() - requestStartedAt)
                            print("Lexi Buddy Capture latency: firstVisibleToken=\(networkTtftMs)ms")
                        }
                        self.rawCapturePanel.update(status: .buddyStreaming(capture, accumulated))
                    },
                    onTiming: { timing in
                        if let proxyTtftMs = timing.proxyTtftMs, let anthropicTtftMs = timing.anthropicTtftMs {
                            print("Lexi Buddy proxy timing: proxyTtft=\(proxyTtftMs)ms anthropicTtft=\(anthropicTtftMs)ms")
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let stack = LookupNavigationStack(
                        rootTerm: capture.displayTitle,
                        sourceText: capture.sourceText,
                        answer: answer,
                        appName: capture.appName,
                        windowTitle: capture.windowTitle,
                        sourceLabel: "Buddy Capture"
                    )
                    self.lastAnswer = answer
                    self.rawCapturePanel.update(status: .lookup(stack))
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription.isEmpty ? "Couldn't explain that Buddy Capture — try again." : error.localizedDescription
                await MainActor.run {
                    self.rawCapturePanel.update(status: .buddyError(capture, message))
                }
            }
        }
    }

    private func requestNestedExplanation(term: String, stack parentStack: LookupNavigationStack) {
        explainTask?.cancel()
        guard let childId = rawCapturePanel.beginNestedLookup(term: term) else { return }
        lastAnswer = rawCapturePanel.currentAnswer
        rebuildMenu()

        explainTask = Task { [weak self] in
            guard let self else { return }
            do {
                let requestStartedAt = currentMilliseconds()
                let client = ExplainClient()
                let answer = try await client.explainNested(term: term, in: parentStack) { [weak self] _, accumulated in
                    guard let self else { return }
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
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription.isEmpty ? "Couldn't explain that nested term — try again." : error.localizedDescription
                await MainActor.run {
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
                let answer = try await client.explain(capture) { [weak self] _, accumulated in
                    guard let self else { return }
                    if !didLogFirstToken {
                        didLogFirstToken = true
                        let appTtftMs = Int(self.currentMilliseconds() - hotkeyStartedAt)
                        let networkTtftMs = Int(self.currentMilliseconds() - requestStartedAt)
                        print("Lexi latency: firstVisibleToken=\(appTtftMs)ms networkAndModel=\(networkTtftMs)ms")
                    }
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
                    self.rawCapturePanel.update(status: .lookup(stack))
                    self.rebuildMenu()
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription.isEmpty ? "Couldn't reach the assistant — try again." : error.localizedDescription
                await MainActor.run {
                    self.rawCapturePanel.update(status: .error(capture, message))
                }
            }
        }
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
