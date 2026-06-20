import Cocoa

struct ClaudeResponse: Codable {
    let content: [Content]
    let id: String
    let model: String
    let role: String
    let stopReason: String?
    let type: String
    let usage: Usage?
    
    struct Content: Codable {
        let text: String
        let type: String
    }
    
    struct Usage: Codable {
        let inputTokens: Int
        let outputTokens: Int
    }
}

class ClaudeAIService {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let session = URLSession.shared
    private let accessibilityManager: AccessibilityManager?
    
    init(apiKey: String, accessibilityManager: AccessibilityManager? = nil) {
        self.apiKey = apiKey
        self.accessibilityManager = accessibilityManager
    }
    
    func explainTerm(term: String, context: String, learningStyle: LearningStyle = .analogies, appName: String = "Unknown", screenshot: Data? = nil, onStreamingChunk: ((String) -> Void)? = nil, isNested: Bool = false, inferredActivity: String? = nil) async throws -> String {
        print("\n" + String(repeating: "=", count: 60))
        print("STEP 4: CLAUDE AI SERVICE - RECEIVING REQUEST")
        print(String(repeating: "=", count: 60))
        print("Term: '\(term)'")
        print("App: \(appName)")
        print("Context length: \(context.count) characters")
        print("Screenshot: \(screenshot?.count ?? 0) bytes")
        
        if context.isEmpty && screenshot == nil {
            print("❌ STEP 4 FAILED: Both context and screenshot are EMPTY!")
        } else {
            print("✅ STEP 4: Context/screenshot received successfully")
            if !context.isEmpty {
                print("✅ Context preview: \(String(context.prefix(200)))...")
            }
        }
        
        guard !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
        }
        
        // Check cache first
        if let cachedExplanation = CacheService.shared.getExplanation(for: term, learningStyle: learningStyle) {
            print("Cache hit for: \(term)")
            return cachedExplanation
        }
        
        // Use streaming with Vision API
        let explanation = try await streamExplanation(term: term, context: context, learningStyle: learningStyle, appName: appName, screenshot: screenshot, onStreamingChunk: onStreamingChunk, isNested: isNested, inferredActivity: inferredActivity)
        
        // Cache the result
        CacheService.shared.setExplanation(explanation, for: term, learningStyle: learningStyle)
        
        print("✅ STEP 4 COMPLETE: Streaming explanation received")
        print(String(repeating: "=", count: 60) + "\n")
        
        return explanation
    }
    
    private func streamExplanation(term: String, context: String, learningStyle: LearningStyle, appName: String, screenshot: Data?, onStreamingChunk: ((String) -> Void)?, isNested: Bool, inferredActivity: String?) async throws -> String {
        let prompt = buildDynamicPrompt(term: term, context: context, learningStyle: learningStyle, appName: appName, isNested: isNested, inferredActivity: inferredActivity)
        
        print("✅ STEP 4: Prompt built")
        print("\n" + String(repeating: "=", count: 80))
        print("STEP 5: SENDING STREAMING REQUEST TO VISION API")
        print(String(repeating: "=", count: 80))
        print("API: \(baseURL)")
        print("Model: claude-sonnet-4-6")
        print("Prompt length: \(prompt.count) characters")
        print("Screenshot: \(screenshot?.count ?? 0) bytes")
        
        // Build messages array with optional image
        var messages: [[String: Any]] = []
        
        if let screenshot = screenshot {
            let base64Image = screenshot.base64EncodedString()
            messages = [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        } else {
            messages = [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        }
        
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1000,
            "messages": messages,
            "stream": true,
            "temperature": 0.7
        ]
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        print("✅ Starting streaming request...")
        print(String(repeating: "=", count: 80) + "\n")
        
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ API Error: \(httpResponse.statusCode)")
            print("Response headers: \(httpResponse.allHeaderFields)")
            throw ClaudeError.apiError(httpResponse.statusCode)
        }
        
        var fullResponse = ""
        var lineCount = 0
        
        for try await line in bytes.lines {
            lineCount += 1
            print("📡 Line \(lineCount): \(line.prefix(200))")
            
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                print("📦 JSON: \(jsonString)")
                
                if jsonString == "[DONE]" {
                    print("✅ Stream complete")
                    break
                }
                
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let eventType = json["type"] as? String
                    
                    if eventType == "thinking",
                       let delta = json["thinking"] as? String {
                        print("💭 Thinking: '\(delta.prefix(200))...'")
                        onStreamingChunk?("[Thinking]\n\(delta)")
                    } else if eventType == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       let deltaType = delta["type"] as? String,
                       deltaType == "text_delta",
                       let text = delta["text"] as? String {
                        fullResponse += text
                        print("📥 Streaming: '\(text)'")
                        onStreamingChunk?(fullResponse)
                    } else if let delta = json["delta"] as? [String: Any],
                              let text = delta["text"] as? String {
                        // Fallback for older event shapes
                        fullResponse += text
                        print("📥 Streaming (fallback): '\(text)'")
                        onStreamingChunk?(fullResponse)
                    } else if eventType == "message_stop" {
                        print("✅ Stream complete")
                        break
                    } else {
                        print("⚠️ Unhandled stream event: \(eventType ?? "unknown")")
                    }
                } else {
                    print("⚠️ Failed to parse JSON or extract text")
                }
            }
        }
        
        print("\n✅ Streaming complete: \(fullResponse.count) characters")
        
        return fullResponse
    }
    
    private func buildDynamicPrompt(term: String, context: String, learningStyle: LearningStyle, appName: String, isNested: Bool, inferredActivity: String?) -> String {
        var promptParts: [String] = []
        
        // Varied system prompts based on randomness
        let systemPrompts = [
            "You are an expert explainer who adapts to any context. Be creative, varied, and engaging in your explanations.",
            "You are a knowledgeable guide who makes complex ideas accessible. Use fresh language and avoid clichés.",
            "You are a versatile explainer who can adapt to any learning style. Be dynamic and avoid formulaic responses.",
            "You are a master teacher who explains concepts in unique ways. Keep it fresh and interesting.",
            "You are an adaptive explainer who tailors content to the context. Be original and engaging."
        ]
        guard let randomSystemPrompt = systemPrompts.randomElement() else {
            return "You are an expert explainer who adapts to any context."
        }
        
        promptParts.append(randomSystemPrompt)
        
        // Add inferred activity naturally with variation
        if let activity = inferredActivity {
            let activityPhrases = [
                "The user is currently: \(activity)",
                "Context: The user is \(activity)",
                "The user's activity: \(activity)"
            ]
            if let phrase = activityPhrases.randomElement() {
                promptParts.append("\n\(phrase)")
            }
        }
        
        // Varied context introductions
        let introPhrases = [
            "The user highlighted \"\(term)\" in \(appName) and wants to understand it.",
            "In the app \(appName), the user selected \"\(term)\" seeking clarification.",
            "Working in \(appName), the user came across \"\(term)\" and needs an explanation.",
            "The term \"\(term)\" was highlighted in \(appName) - what does it mean here?"
        ]
        
        if isNested {
            let nestedPhrases = [
                "Within the previous explanation, the user highlighted \"\(term)\" for deeper understanding.",
                "While reading, the user selected \"\(term)\" to explore it further in context.",
                "The user is diving deeper by highlighting \"\(term)\" in the explanation."
            ]
            if let phrase = nestedPhrases.randomElement() {
                promptParts.append("\n\(phrase)")
            }
        } else {
            if let phrase = introPhrases.randomElement() {
                promptParts.append("\n\(phrase)")
            }
        }
        
        // Add context with varied phrasing
        if !context.isEmpty {
            let contextPhrases = [
                "Here's the surrounding text:\n\n\(context)",
                "Context around the term:\n\n\(context)",
                "The term appears in this context:\n\n\(context)",
                "Surrounding content:\n\n\(context)"
            ]
            if let phrase = contextPhrases.randomElement() {
                promptParts.append("\n\(phrase)")
            }
        }
        
        // Add context-specific guidance with variety
        let contextType = determineContextType(appName: appName)
        
        switch contextType {
        case .coding:
            let codingGuidance = [
                "Focus on technical implementation and practical code examples.",
                "Explain with code context and practical programming insights.",
                "Highlight how this works in actual code with examples.",
                "Provide technical depth with real-world code scenarios."
            ]
            if let guidance = codingGuidance.randomElement() {
                promptParts.append("\n\(guidance)")
            }
        case .social:
            let socialGuidance = [
                "Consider informal language, slang, and social media conventions.",
                "Factor in social context, abbreviations, and informal communication style.",
                "Account for the casual nature of social media communication.",
                "Consider how this term is used in social contexts."
            ]
            if let guidance = socialGuidance.randomElement() {
                promptParts.append("\n\(guidance)")
            }
        case .reading:
            let readingGuidance = [
                "Focus on narrative flow and informational context.",
                "Consider the reading context and informational purpose.",
                "Explain in a way that fits the reading material's tone.",
                "Maintain the perspective of informational or narrative content."
            ]
            if let guidance = readingGuidance.randomElement() {
                promptParts.append("\n\(guidance)")
            }
        case .notes:
            let notesGuidance = [
                "Consider this as personal knowledge management or study context.",
                "Frame the explanation for note-taking and learning purposes.",
                "Provide clarity suitable for personal reference.",
                "Make it useful for knowledge retention and understanding."
            ]
            if let guidance = notesGuidance.randomElement() {
                promptParts.append("\n\(guidance)")
            }
        case .general:
            let generalGuidance = [
                "Explain what \"\(term)\" means specifically in this context.",
                "Focus on the contextual meaning of \"\(term)\".",
                "Clarify \"\(term)\" within this specific situation.",
                "Provide context-appropriate meaning for \"\(term)\"."
            ]
            if let guidance = generalGuidance.randomElement() {
                promptParts.append("\n\(guidance)")
            }
        }
        
        // Varied final instruction
        let finalInstructions = [
            "Now, explain \"\(term)\" in this context:",
            "Your explanation of \"\(term)\":",
            "What does \"\(term)\" mean here?",
            "Explain \"\(term)\" for this context:",
            "Provide your explanation of \"\(term)\":"
        ]
        if let instruction = finalInstructions.randomElement() {
            promptParts.append("\n\(instruction)")
        }
        
        return promptParts.joined()
    }
    
    private func determineContextType(appName: String) -> ContextType {
        let lowerAppName = appName.lowercased()
        
        if lowerAppName.contains("xcode") || lowerAppName.contains("vscode") || lowerAppName.contains("intellij") || lowerAppName.contains("pycharm") || lowerAppName.contains("terminal") || lowerAppName.contains("vim") || lowerAppName.contains("neovim") {
            return .coding
        } else if lowerAppName.contains("safari") || lowerAppName.contains("chrome") || lowerAppName.contains("edge") || lowerAppName.contains("firefox") {
            return .reading
        } else if lowerAppName.contains("twitter") || lowerAppName.contains("x.com") || lowerAppName.contains("slack") || lowerAppName.contains("discord") || lowerAppName.contains("messages") {
            return .social
        } else if lowerAppName.contains("notion") || lowerAppName.contains("obsidian") || lowerAppName.contains("evernote") || lowerAppName.contains("notes") {
            return .notes
        } else {
            return .general
        }
    }
    
    private enum ContextType {
        case coding
        case reading
        case social
        case notes
        case general
    }
}

enum ClaudeError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(Int)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key provided"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let code):
            return "API error with status code: \(code)"
        }
    }
}