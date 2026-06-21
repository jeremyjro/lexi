import AppKit
import ApplicationServices
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionOnboarding: PermissionOnboardingWindowController?
    private let hotkeyManager = HotkeyManager()
    private let selectionCapture = SelectionCapture()
    private let rawCapturePanel = RawCapturePanelController()
    private let explainClient = ExplainClient()
    private var explainTask: Task<Void, Never>?
    private var legacyModifierMonitor: Any?
    private var isEnabled = true
    private var isOptionCommandHeld = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        rawCapturePanel.onDismiss = { [weak self] in
            self?.explainTask?.cancel()
        }

        requestAccessibilityPermission()
        let isTrusted = AXIsProcessTrusted()
        print("Accessibility trusted: \(isTrusted)")

        if !isTrusted {
            print("Accessibility permission is not enabled")
            showPermissionOnboarding()
        }

        setupGlobalHotkey()
        print("Lexi started successfully")
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

        let hotkeyItem = NSMenuItem(title: "Hotkeys…", action: #selector(showHotkeyInfo), keyEquivalent: "")
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)

        let permissionItem = NSMenuItem(title: "Re-check Accessibility Permission", action: #selector(recheckPermission), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

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
            rawCapturePanel.hide()
        }
        rebuildMenu()
    }

    @objc private func showHotkeyInfo() {
        let alert = NSAlert()
        alert.messageText = "Lexi hotkeys"
        alert.informativeText = "Option + Space is the default lookup hotkey. Option + Command is still available as a fallback during local testing."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func recheckPermission() {
        if AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility permission is enabled"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else {
            requestAccessibilityPermission()
            showPermissionOnboarding()
        }
    }

    @objc private func quitLexi() {
        NSApp.terminate(nil)
    }

    func setupGlobalHotkey() {
        print("Setting up Option+Space global hotkey...")
        hotkeyManager.registerOptionSpace { [weak self] in
            self?.handleLookupHotkey()
        }
        installLegacyOptionCommandFallback()
        print("Option+Space hotkey registered")
        print("Option+Command legacy fallback registered")
    }

    private func installLegacyOptionCommandFallback() {
        legacyModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierKeys(event: event)
        }
    }

    private func handleLookupHotkey() {
        let hotkeyStartedAt = currentMilliseconds()
        guard isEnabled else { return }

        if rawCapturePanel.isVisible {
            explainTask?.cancel()
            rawCapturePanel.hide()
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

    private func requestExplanation(for capture: CapturedSelection, hotkeyStartedAt: Double) {
        explainTask?.cancel()
        explainTask = Task { [weak self] in
            guard let self else { return }
            var didLogFirstToken = false

            do {
                let requestStartedAt = currentMilliseconds()
                let answer = try await explainClient.explain(capture) { [weak self] _, accumulated in
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
                    self.rawCapturePanel.update(status: .answered(capture, answer))
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

    private func handleModifierKeys(event: NSEvent) {
        let optionHeld = event.modifierFlags.contains(.option)
        let commandHeld = event.modifierFlags.contains(.command)
        let bothHeld = optionHeld && commandHeld

        if bothHeld && !isOptionCommandHeld {
            isOptionCommandHeld = true
            print("Option+Command armed; capture will run on release")
        } else if !bothHeld && isOptionCommandHeld {
            isOptionCommandHeld = false
            print("Option+Command released; running capture")
            handleLookupHotkey()
        }
    }

    private func currentMilliseconds() -> Double {
        Date().timeIntervalSince1970 * 1000
    }
}
