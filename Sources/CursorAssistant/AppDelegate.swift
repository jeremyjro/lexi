import AppKit
import Foundation

func loadDotEnv() {
    // Try multiple possible locations for .env file
    let possiblePaths = [
        Bundle.main.path(forResource: ".env", ofType: nil),
        FileManager.default.currentDirectoryPath.appending("/.env"),
        "/Volumes/T7/Projects/Jeremy/CursorAssistant/.env"  // Direct path to project
    ].compactMap { $0 }
    
    var envPath: String?
    var contents: String?
    
    for path in possiblePaths {
        if let fileContents = try? String(contentsOfFile: path, encoding: .utf8) {
            envPath = path
            contents = fileContents
            print("✅ Found .env file at: \(path)")
            break
        }
    }
    
    guard let _ = envPath, let fileContents = contents else {
        print("⚠️ Could not load .env file from any of these locations:")
        for path in possiblePaths {
            print("  - \(path)")
        }
        return
    }
    
    fileContents.split(separator: "\n").forEach { line in
        let parts = line.split(separator: "=", maxSplits: 1)
        if parts.count == 2 {
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            setenv(key, value, 1)
            print("✅ Loaded environment variable: \(key)")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var accessibilityManager: AccessibilityManager?
    var aiService: ClaudeAIService?
    var bubbleController: BubbleController?
    var screenCaptureManager: ScreenCaptureManager?
    var contextInferenceService: ContextInferenceService?
    private var isOptionCommandHeld = false
    private var lastSelectedText: String = ""
    private var tabManager = TabManager()
    private var isClosingMode = false  // Track if we're closing vs capturing
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load environment variables from .env file
        loadDotEnv()
        
        // Load API key from environment
        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        
        // Initialize services
        accessibilityManager = AccessibilityManager()
        screenCaptureManager = ScreenCaptureManager()
        contextInferenceService = ContextInferenceService(apiKey: apiKey)
        aiService = ClaudeAIService(apiKey: apiKey, accessibilityManager: accessibilityManager)
        bubbleController = BubbleController()
        
        // Request accessibility permissions
        accessibilityManager?.requestPermissions()
        
        // Check if accessibility is trusted
        let isTrusted = AXIsProcessTrusted()
        print("Accessibility trusted: \(isTrusted)")
        
        if !isTrusted {
            print("⚠️ WARNING: Accessibility permissions not granted!")
            print("Please grant accessibility permissions in System Settings > Privacy & Security > Accessibility")
        }
        
        // Setup global hotkey
        setupGlobalHotkey()
        
        print("Lexi started successfully")
    }
    
    func setupGlobalHotkey() {
        print("Setting up global hotkey monitor...")

        // Use Option+Command as the trigger
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            print("🔹 FlagsChanged event received - Option: \(event.modifierFlags.contains(.option)), Command: \(event.modifierFlags.contains(.command))")
            self?.handleModifierKeys(event: event)
        }

        print("✅ FlagsChanged monitor added")
    }

    func handleModifierKeys(event: NSEvent) {
        print("🎹 MODIFIER KEYS - Option: \(event.modifierFlags.contains(.option)), Command: \(event.modifierFlags.contains(.command))")

        let optionHeld = event.modifierFlags.contains(.option)
        let commandHeld = event.modifierFlags.contains(.command)
        let bothHeld = optionHeld && commandHeld

        if bothHeld && !isOptionCommandHeld {
            isOptionCommandHeld = true
            print("✅ Option+Command PRESSED")

            // If bubble is visible, close it (toggle behavior)
            if bubbleController?.isBubbleVisible() == true {
                print("Closing bubble (toggle)")
                bubbleController?.hideBubble()
                isClosingMode = true  // Set close mode to prevent text processing
                return
            }

            // Not in close mode, so we're capturing
            isClosingMode = false

            // Show capturing state at bottom center
            bubbleController?.showBubble(at: NSEvent.mouseLocation, state: .capturing, onClose: { [weak self] in
                self?.bubbleController?.hideBubble()
            })

            // Start tracking cursor and text selection
            accessibilityManager?.startTracking()
        } else if !bothHeld && isOptionCommandHeld {
            isOptionCommandHeld = false

            // If we were in close mode, don't process text
            if isClosingMode {
                print("In close mode, skipping text processing")
                isClosingMode = false
                return
            }

            print("Option+Command released")

            // Check if text is selected
            if let selectedText = accessibilityManager?.stopTrackingAndGetSelection(), !selectedText.isEmpty {
                print("📝 Text selected on Option+Command release: '\(selectedText)'")

                // Determine if popup is currently open
                let isPopupOpen = bubbleController?.isBubbleVisible() ?? false

                if isPopupOpen {
                    // Popup is open - add new tab
                    print("➕ Popup open, adding new tab for: '\(selectedText)'")
                    processSelectedText(selectedText, parentTerm: tabManager.activeTab?.term)
                } else {
                    // Popup is closed - open with new explanation
                    print("🔓 Popup closed, opening with explanation for: '\(selectedText)'")
                    processSelectedText(selectedText)
                }
            } else {
                // No text selected - close popup if open
                if bubbleController?.isBubbleVisible() ?? false {
                    print("❌ No text selected, closing popup")
                    bubbleController?.hideBubble()
                } else {
                    print("ℹ️ No text selected and popup already closed")
                }
            }
        }
    }
    
    
    
    func processSelectedText(_ text: String, parentTerm: String? = nil) {
        guard !text.isEmpty else { return }

        lastSelectedText = text // Store for retry
        print("\n" + String(repeating: "=", count: 60))
        print("STEP 3: PROCESSING SELECTED TEXT")
        print(String(repeating: "=", count: 60))
        print("Selected term: '\(text)'")
        if let parent = parentTerm {
            print("Parent term: '\(parent)'")
        }

        // Collect context and infer user's intent
        let context = contextInferenceService?.collectContext() ?? AppContext(
            appName: "Unknown",
            bundleIdentifier: nil,
            windowTitle: nil,
            selectedText: text,
            surroundingText: nil,
            inferredActivity: nil,
            screenshotData: nil
        )
        
        let surroundingText = context.surroundingText ?? ""
        let screenshot = context.screenshotData

        print("✅ STEP 3: App context: \(context.appName)")
        print("✅ STEP 3: Window: \(context.windowTitle ?? "Unknown")")
        print("✅ STEP 3: Context received: \(surroundingText.count) characters")
        print("✅ STEP 3: Screenshot captured: \(screenshot?.count ?? 0) bytes")

        if surroundingText.isEmpty && screenshot == nil {
            print("❌ STEP 3 FAILED: Both context and screenshot are EMPTY!")
        } else {
            if !surroundingText.isEmpty {
                print("✅ Context preview: \(String(surroundingText.prefix(200)))...")
            }
        }

        print(String(repeating: "=", count: 60) + "\n")

        // Show loading bubble or update existing tab
        if parentTerm == nil {
            // This is the initial explanation - show streaming state with empty content
            bubbleController?.updateStreamingContent("")
            bubbleController?.showBubble(at: NSEvent.mouseLocation, state: .streaming(""), onClose: { [weak self] in
                self?.bubbleController?.hideBubble()
            })
        }

        // Request explanation from AI with context inference
        Task {
            var inferredActivity: String? = nil
            
            // Infer user's activity (the magic part!)
            if let inferenceService = contextInferenceService {
                inferredActivity = await inferenceService.inferActivity(context: context)
                print("🧠 Inferred activity: \(inferredActivity ?? "Unknown")")
            }
            
            do {
                guard let aiService = aiService else {
                    await MainActor.run {
                        bubbleController?.showBubble(at: NSEvent.mouseLocation, state: .error("AI service not initialized"), onRetry: { [weak self] in
                            self?.retryLastRequest()
                        }, onClose: { [weak self] in
                            self?.bubbleController?.hideBubble()
                        })
                    }
                    return
                }
                
                let explanation = try await aiService.explainTerm(
                    term: text,
                    context: surroundingText,
                    learningStyle: .analogies,
                    appName: context.appName,
                    screenshot: screenshot,
                    onStreamingChunk: { [weak self] streamingContent in
                        // Immediate smooth chunk updates
                        Task { @MainActor in
                            self?.bubbleController?.updateStreamingContent(streamingContent)
                        }
                    },
                    isNested: parentTerm != nil,
                    inferredActivity: inferredActivity
                )
                
                // Add tab with explanation
                await MainActor.run {
                    if parentTerm == nil {
                        // First explanation - create new tab manager
                        tabManager.addTab(term: text, explanation: explanation)
                    } else {
                        // Nested explanation - add to existing tab manager
                        tabManager.addTab(term: text, explanation: explanation, parentTerm: parentTerm)
                    }
                    
                    // Show tabbed result
                    bubbleController?.showBubble(at: NSEvent.mouseLocation, state: .result(tabManager), onClose: { [weak self] in
                        self?.bubbleController?.hideBubble()
                    }, onTextSelected: { [weak self] selectedText in
                        // Handle recursive explanation
                        print("📝 User selected text within bubble: '\(selectedText)'")
                        self?.processSelectedText(selectedText, parentTerm: text)
                    }, onFollowUpPrompt: { [weak self] followUpQuestion, completion in
                        // Handle follow-up question
                        print("💬 Follow-up question: '\(followUpQuestion)'")
                        self?.processFollowUpPrompt(followUpQuestion, completion: completion)
                    })
                }
            } catch let claudeError as ClaudeError {
                print("Claude API error: \(claudeError)")
                await MainActor.run {
                    let detailedError = getDetailedErrorMessage(for: claudeError)
                    bubbleController?.showBubble(at: NSEvent.mouseLocation, state: .error(detailedError), onRetry: { [weak self] in
                        self?.retryLastRequest()
                    }, onClose: { [weak self] in
                        self?.bubbleController?.hideBubble()
                    })
                }
            } catch {
                print("Unexpected error processing text: \(error)")
                await MainActor.run {
                    bubbleController?.showBubble(at: NSEvent.mouseLocation, state: .error("Failed to process: \(error.localizedDescription)"), onRetry: { [weak self] in
                        self?.retryLastRequest()
                    }, onClose: { [weak self] in
                        self?.bubbleController?.hideBubble()
                    })
                }
            }
        }
    }
    
    func processFollowUpPrompt(_ question: String, completion: @escaping () -> Void) {
        guard let activeTab = tabManager.activeTab else { return }
        
        print("\n" + String(repeating: "=", count: 60))
        print("STEP: PROCESSING FOLLOW-UP QUESTION")
        print(String(repeating: "=", count: 60))
        print("Question: '\(question)'")
        print("Context term: '\(activeTab.term)'")
        
        // Show streaming state
        bubbleController?.showBubble(at: NSEvent.mouseLocation, state: .streaming(activeTab.explanation), onClose: { [weak self] in
            self?.bubbleController?.hideBubble()
        }, onTextSelected: { [weak self] selectedText in
            self?.processSelectedText(selectedText, parentTerm: activeTab.term)
        }, onFollowUpPrompt: { [weak self] followUpQuestion, completion in
            self?.processFollowUpPrompt(followUpQuestion, completion: completion)
        })
        
        Task {
            do {
                guard let aiService = aiService else { return }
                
                // Build a prompt for the follow-up question
                let followUpPrompt = """
                The user previously asked about "\(activeTab.term)" and received this explanation:
                
                \(activeTab.explanation)
                
                Now they have a follow-up question: "\(question)"
                
                Please answer their follow-up question, building on the previous explanation. Keep it concise and focused.
                """
                
                let response = try await aiService.explainTerm(
                    term: activeTab.term,
                    context: followUpPrompt,
                    learningStyle: .analogies,
                    appName: "CursorAssistant",
                    screenshot: nil,
                    onStreamingChunk: { [weak self] streamingContent in
                        Task { @MainActor in
                            self?.bubbleController?.updateStreamingContent(streamingContent)
                        }
                    },
                    isNested: true
                )
                
                // Update the active tab's explanation
                await MainActor.run {
                    let updatedExplanation = "\(activeTab.explanation)\n\n---\n\n\(response)"
                    if let index = tabManager.tabs.firstIndex(where: { $0.id == activeTab.id }) {
                        tabManager.tabs[index].explanation = updatedExplanation
                    }
                    
                    // Call completion to stop processing animation
                    completion()
                    
                    // Show updated result
                    bubbleController?.showBubble(at: NSEvent.mouseLocation, state: .result(tabManager), onClose: { [weak self] in
                        self?.bubbleController?.hideBubble()
                    }, onTextSelected: { [weak self] selectedText in
                        self?.processSelectedText(selectedText, parentTerm: activeTab.term)
                    }, onFollowUpPrompt: { [weak self] followUpQuestion, completion in
                        self?.processFollowUpPrompt(followUpQuestion, completion: completion)
                    })
                }
            } catch {
                print("Error processing follow-up: \(error)")
            }
        }
    }
    
    private func retryLastRequest() {
        guard !lastSelectedText.isEmpty else { return }
        print("Retrying request for: \(lastSelectedText)")
        processSelectedText(lastSelectedText)
    }
    
    private func getDetailedErrorMessage(for error: ClaudeError) -> String {
        switch error {
        case .noAPIKey:
            return "API key missing. Please add ANTHROPIC_API_KEY to .env file"
        case .invalidResponse:
            return "Invalid response from API. Check your internet connection"
        case .apiError(let code):
            switch code {
            case 401:
                return "Authentication failed. Check your API key"
            case 404:
                return "Model not found. The AI model may be unavailable"
            case 429:
                return "Rate limit exceeded. Please try again later"
            case 500:
                return "API server error. Please try again later"
            default:
                return "API error (code: \(code)). Please try again"
            }
        }
    }
}