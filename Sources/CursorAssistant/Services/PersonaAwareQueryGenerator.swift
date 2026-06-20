import Foundation

class PersonaAwareQueryGenerator {
    private let apiKey: String
    private let baseURL: String = "https://api.anthropic.com/v1"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func generateInferredQuery(
        highlightedText: String,
        surroundingContext: String,
        appContext: EnhancedAppContext,
        userProfile: UserProfile
    ) async -> InferredQuery {
        
        // Build persona-specific system prompt
        let systemPrompt = buildPersonaSystemPrompt(
            persona: userProfile.persona,
            appContext: appContext,
            explanationStyle: userProfile.preferredExplanationStyle
        )
        
        // Build context-aware user prompt
        let userPrompt = buildContextPrompt(
            highlightedText: highlightedText,
            surroundingContext: surroundingContext,
            appContext: appContext,
            userProfile: userProfile
        )
        
        do {
            let response = try await makeClaudeRequest(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
            
            return parseInferenceResponse(
                response: response,
                originalText: highlightedText,
                appContext: appContext
            )
        } catch {
            print("Query generation error: \(error)")
            return fallbackQuery(
                highlightedText: highlightedText,
                appContext: appContext,
                userProfile: userProfile
            )
        }
    }
    
    private func buildPersonaSystemPrompt(
        persona: UserPersona,
        appContext: EnhancedAppContext,
        explanationStyle: ExplanationStyle
    ) -> String {
        var prompt = """
        You are a query inference assistant that predicts what a user wants to know based on their highlighted text and context.
        
        USER PERSONA: \(persona.displayName)
        \(persona.description)
        
        KNOWLEDGE GAPS: This user typically struggles with: \(persona.knowledgeGaps.joined(separator: ", "))
        
        PREFERRED EXPLANATION STYLE: \(explanationStyle.systemPrompt)
        
        CURRENT CONTEXT:
        - App: \(appContext.appName) (\(appContext.appCategory.rawValue))
        - Content Type: \(appContext.contentType.rawValue)
        
        Your task is to infer EXACTLY what question this user would type if they were to ask about the highlighted text.
        Consider their persona, knowledge gaps, and the current context.
        
        Respond in JSON format with this structure:
        {
            "inferred_question": "the exact question the user would ask",
            "confidence": 0.0-1.0,
            "reasoning": "why you inferred this question based on persona and context",
            "explanation_approach": "one of: \(ExplanationApproach.allCases.map { $0.rawValue }.joined(separator: ", "))",
            "alternative_questions": ["alternative 1", "alternative 2"],
            "needs_external_lookup": true/false,
            "external_lookup_source": "source name or null"
        }
        """
        
        // Add context-specific guidance
        switch appContext.appCategory {
        case .socialMedia:
            prompt += """
            
            SOCIAL MEDIA CONTEXT:
            - Users often encounter technical terms in business/product content
            - Go-to-market personas highlight technical terms to understand business implications
            - Questions often focus on "why does this matter?" rather than pure definitions
            """
        case .messaging:
            prompt += """
            
            MESSAGING CONTEXT:
            - Users encounter slang, abbreviations, insider language
            - Questions often focus on "what does this mean in this context?"
            - May need urban dictionary or casual explanation sources
            """
        case .codeEditor:
            prompt += """
            
            CODE EDITOR CONTEXT:
            - Technical personas focus on implementation details
            - Non-technical personas need business/strategic context
            - Questions may be about "how does this work?" or "why is this used?"
            """
        default:
            break
        }
        
        return prompt
    }
    
    private func buildContextPrompt(
        highlightedText: String,
        surroundingContext: String,
        appContext: EnhancedAppContext,
        userProfile: UserProfile
    ) -> String {
        var prompt = """
        HIGHLIGHTED TEXT: "\(highlightedText)"
        
        SURROUNDING CONTEXT:
        \(surroundingContext)
        
        APP CONTEXT:
        - Application: \(appContext.appName)
        - Window Title: \(appContext.windowTitle ?? "Unknown")
        - Category: \(appContext.appCategory.rawValue)
        - Content Type: \(appContext.contentType.rawValue)
        
        USER CONTEXT:
        - Persona: \(userProfile.persona.displayName)
        - Knowledge Gaps: \(userProfile.persona.knowledgeGaps.joined(separator: ", "))
        
        Based on this user's persona and the context, what EXACT question would they ask about this highlighted text?
        
        Consider:
        1. What would this persona typically NOT understand?
        2. What question would help them understand the term in THIS specific context?
        3. How would they phrase this question naturally?
        4. What explanation approach would work best for them?
        
        Return your response as a JSON object.
        """
        
        return prompt
    }
    
    private func makeClaudeRequest(
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": userPrompt
            ]
        ]
        
        let payload: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "max_tokens": 500,
            "system": systemPrompt,
            "messages": messages,
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
                throw InferenceError.apiError("Invalid response")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let text = firstContent["text"] as? String else {
            throw InferenceError.parseError("Could not parse response")
        }
        
        return text
    }
    
    private func parseInferenceResponse(
        response: String,
        originalText: String,
        appContext: EnhancedAppContext
    ) -> InferredQuery {
        do {
            guard let data = response.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InferenceError.parseError("Invalid JSON")
            }
            
            let inferredQuestion = json["inferred_question"] as? String ?? "What does \(originalText) mean?"
            let confidence = json["confidence"] as? Double ?? 0.5
            let reasoning = json["reasoning"] as? String ?? "Based on context analysis"
            let approachRaw = json["explanation_approach"] as? String ?? ExplanationApproach.definition.rawValue
            let explanationApproach = ExplanationApproach(rawValue: approachRaw) ?? .definition
            let alternativeQuestions = json["alternative_questions"] as? [String] ?? []
            let needsExternalLookup = json["needs_external_lookup"] as? Bool ?? false
            let externalLookupSource = json["external_lookup_source"] as? String
            
            return InferredQuery(
                originalText: originalText,
                inferredQuestion: inferredQuestion,
                confidence: confidence,
                reasoning: reasoning,
                suggestedExplanationApproach: explanationApproach,
                alternativeQuestions: alternativeQuestions,
                needsExternalLookup: needsExternalLookup,
                externalLookupSource: externalLookupSource
            )
        } catch {
            print("Parse error: \(error)")
            return fallbackQuery(highlightedText: originalText, appContext: appContext, userProfile: .defaultProfile)
        }
    }
    
    private func fallbackQuery(
        highlightedText: String,
        appContext: EnhancedAppContext,
        userProfile: UserProfile
    ) -> InferredQuery {
        // Generate persona-appropriate fallback query
        let baseQuestion: String
        var approach: ExplanationApproach
        
        switch userProfile.persona {
        case .goToMarket:
            baseQuestion = "What does '\(highlightedText)' mean from a business perspective, and why is it important in this context?"
            approach = .business
        case .technical:
            baseQuestion = "What is the technical definition and implementation of '\(highlightedText)'?"
            approach = .technical
        case .executive:
            baseQuestion = "What are the strategic implications of '\(highlightedText)' in this context?"
            approach = .business
        case .student:
            baseQuestion = "Can you explain '\(highlightedText)' in simple terms with examples?"
            approach = .simplified
        case .general:
            baseQuestion = "What does '\(highlightedText)' mean in this context?"
            approach = .definition
        }
        
        // Adjust for app context
        let finalQuestion: String
        switch appContext.appCategory {
        case .messaging:
            finalQuestion = "What does '\(highlightedText)' mean in this conversation context?"
            approach = .context
        case .socialMedia:
            finalQuestion = baseQuestion
        default:
            finalQuestion = baseQuestion
        }
        
        return InferredQuery(
            originalText: highlightedText,
            inferredQuestion: finalQuestion,
            confidence: 0.3,
            reasoning: "Fallback query based on persona and app context",
            suggestedExplanationApproach: approach,
            alternativeQuestions: [
                "Define '\(highlightedText)'",
                "Why is '\(highlightedText)' mentioned here?"
            ],
            needsExternalLookup: appContext.appCategory == .messaging,
            externalLookupSource: appContext.appCategory == .messaging ? "urban_dictionary" : nil
        )
    }
}

enum InferenceError: Error {
    case apiError(String)
    case parseError(String)
    case networkError(Error)
}