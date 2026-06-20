import Foundation
import AppKit
import ApplicationServices

// Legacy AppContext struct - maintained for backward compatibility
struct AppContext {
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let surroundingText: String?
    let inferredActivity: String?
    let screenshotData: Data?
}

class ContextInferenceService {
    private let apiKey: String
    private let baseURL: String = "https://api.anthropic.com/v1"
    private let inferenceOrchestrator: InferenceOrchestrator?
    private let enhancedContextAnalyzer: EnhancedContextAnalyzer
    
    init(apiKey: String, enableEnhancedInference: Bool = true) {
        self.apiKey = apiKey
        self.enhancedContextAnalyzer = EnhancedContextAnalyzer()
        
        if enableEnhancedInference {
            self.inferenceOrchestrator = InferenceOrchestrator(apiKey: apiKey)
        } else {
            self.inferenceOrchestrator = nil
        }
    }
    
    func collectContext() -> AppContext {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(
                appName: "Unknown",
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil,
                surroundingText: nil,
                inferredActivity: nil,
                screenshotData: nil
            )
        }
        
        let appName = frontmostApp.localizedName ?? "Unknown"
        let bundleIdentifier = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        let windowTitle = focusedWindowTitle(from: appElement)
        let selectedText = getSelectedText(from: appElement)
        let surroundingText = getSurroundingText(from: appElement)
        let screenshotData = captureScreenshot()
        
        return AppContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: selectedText,
            surroundingText: surroundingText,
            inferredActivity: nil,
            screenshotData: screenshotData
        )
    }
    
    // New method for enhanced inference
    func inferUserIntent(context: AppContext) async -> String {
        // Use enhanced inference if available
        if let orchestrator = inferenceOrchestrator,
           let selectedText = context.selectedText {
            
            // Privacy check
            guard orchestrator.shouldProcessInference(
                highlightedText: selectedText,
                surroundingContext: context.surroundingText ?? ""
            ) else {
                return "This appears to contain sensitive information. Please highlight non-sensitive text."
            }
            
            // Use enhanced inference
            let response = await orchestrator.inferUserQuery(
                highlightedText: selectedText,
                surroundingContext: context.surroundingText ?? "",
                appName: context.appName,
                bundleIdentifier: context.bundleIdentifier,
                windowTitle: context.windowTitle,
                screenshotData: context.screenshotData
            )
            
            return response.inferredQuery.inferredQuestion
        }
        
        // Fall back to legacy inference
        return await inferActivity(context: context)
    }
    
    func inferActivity(context: AppContext) async -> String {
        // Build context inference prompt
        let metadata = """
        App: \(context.appName)
        Bundle ID: \(context.bundleIdentifier ?? "Unknown")
        Window: \(context.windowTitle ?? "Unknown")
        Selected text: \(context.selectedText ?? "None")
        Surrounding text: \(context.surroundingText ?? "None")
        """
        
        let systemPrompt = """
        You are a context inference assistant. Given app metadata and optionally selected text, infer what the user is likely trying to understand or research in exactly one sentence.
        
        For example:
        - If on Twitter/X with selected text about AI, infer: "User is researching AI terminology on social media"
        - If in a code editor with selected technical term, infer: "User is learning a programming concept"
        - If reading a research paper with selected academic term, infer: "User is studying academic literature"
        - If in a notes app with selected concept, infer: "User is taking notes on a topic"
        
        Be specific and concise. Return exactly one sentence.
        """
        
        let userPrompt = "Analyze the context and infer the user's current intent in exactly one sentence.\n\n\(metadata)"
        
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            
            let messages: [[String: Any]] = [
                [
                    "role": "user",
                    "content": "\(systemPrompt)\n\n\(userPrompt)"
                ]
            ]
            
            let payload: [String: Any] = [
                "model": "claude-3-haiku-20240307",
                "max_tokens": 100,
                "messages": messages
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return fallbackActivity(for: context)
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? String else {
                return fallbackActivity(for: context)
            }
            
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Context inference error: \(error)")
            return fallbackActivity(for: context)
        }
    }
    
    private func fallbackActivity(for context: AppContext) -> String {
        let appName = context.appName
        return "User is highlighting text in \(appName)"
    }
    
    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(from: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }
        if let windowTitle = accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString) {
            return trimmedText(windowTitle)
        }
        return nil
    }
    
    private func getSelectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString) {
            if let selectedText = accessibilityString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
                return trimmedText(selectedText)
            }
        }
        return nil
    }
    
    private func getSurroundingText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString) {
            if let value = accessibilityValue(from: focusedElement, attribute: kAXValueAttribute as CFString) as? String {
                return String(value.prefix(500))
            }
        }
        return nil
    }
    
    private func captureScreenshot() -> Data? {
        guard let screen = NSScreen.main else { return nil }
        
        let rect = screen.frame
        let cgImage = CGDisplayCreateImage(CGMainDisplayID(), rect: rect)
        
        guard let cgImage else { return nil }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let imageData = bitmapRep.representation(using: .png, properties: [:])
        
        return imageData
    }
    
    private func accessibilityElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var result: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &result)
        guard error == .success else { return nil }
        return result as! AXUIElement?
    }
    
    private func accessibilityString(from element: AXUIElement, attribute: CFString) -> String? {
        var result: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &result)
        return error == .success ? result as? String : nil
    }
    
    private func accessibilityValue(from element: AXUIElement, attribute: CFString) -> AnyObject? {
        var result: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &result)
        return error == .success ? result : nil
    }
    
    private func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}