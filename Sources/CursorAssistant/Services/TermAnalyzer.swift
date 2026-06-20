import Foundation

class TermAnalyzer {
    private let apiKey: String
    private let baseURL: String = "https://api.anthropic.com/v1"
    
    // Domain-specific term patterns
    private let technicalPatterns: [String] = [
        "API", "SDK", "REST", "GraphQL", "microservice", "container", "kubernetes",
        "docker", "serverless", "function", "endpoint", "authentication", "authorization",
        "encryption", "latency", "throughput", "bandwidth", "deployment", "CI/CD",
        "repository", "branch", "merge", "commit", "pull request", "framework", "library"
    ]
    
    private let businessPatterns: [String] = [
        "ROI", "KPI", "B2B", "B2C", "SaaS", "MRR", "ARR", "churn", "retention",
        "acquisition", "funnel", "conversion", "pipeline", "deal", "lead", "prospect",
        "quarterly", "fiscal", "revenue", "margin", "EBITDA", "valuation", "equity"
    ]
    
    private let slangPatterns: [String] = [
        "tbh", "imo", "fr", "ngl", "rn", "ikr", "fyi", "asap", "tldr", "dm",
        "pm", "ama", "fomo", "yolo", "ghost", "curve", "lowkey", "highkey", "cap",
        "no cap", "bet", "slay", "tea", "shade", "sus", "rizz", "based", "red flag"
    ]
    
    private let abbreviationPatterns: [String] = [
        "lol", "lmao", "rofl", "omg", "wtf", "btw", "idk", "iirc", "afaik", "imho",
        "ttyl", "brb", "afk", "g2g", "np", "yw", "thx", "pls", "sry", "msg"
    ]
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func analyzeTerm(
        term: String,
        surroundingContext: String,
        appContext: EnhancedAppContext
    ) async -> TermAnalysis {
        
        // First, try rule-based classification
        if let ruleBasedAnalysis = ruleBasedClassification(
            term: term,
            surroundingContext: surroundingContext,
            appContext: appContext
        ) {
            return ruleBasedAnalysis
        }
        
        // Fall back to AI-powered analysis
        return await aiPoweredAnalysis(
            term: term,
            surroundingContext: surroundingContext,
            appContext: appContext
        )
    }
    
    private func ruleBasedClassification(
        term: String,
        surroundingContext: String,
        appContext: EnhancedAppContext
    ) -> TermAnalysis? {
        let lowercasedTerm = term.lowercased()
        
        // Check for emoji
        if term.containsOnlyEmoji {
            return TermAnalysis(
                term: term,
                termType: .emoji,
                confidence: 0.95,
                likelyDomain: nil,
                contextClues: ["contains emoji characters"],
                needsDefinition: false,
                suggestedExplanationApproach: .context
            )
        }
        
        // Check for technical jargon
        if technicalPatterns.contains(where: { lowercasedTerm.contains($0.lowercased()) }) {
            return TermAnalysis(
                term: term,
                termType: .technicalJargon,
                confidence: 0.85,
                likelyDomain: "technology/engineering",
                contextClues: ["matches technical vocabulary"],
                needsDefinition: true,
                suggestedExplanationApproach: .technical
            )
        }
        
        // Check for business terms
        if businessPatterns.contains(where: { lowercasedTerm.contains($0.lowercased()) }) {
            return TermAnalysis(
                term: term,
                termType: .domainSpecific,
                confidence: 0.85,
                likelyDomain: "business",
                contextClues: ["matches business vocabulary"],
                needsDefinition: true,
                suggestedExplanationApproach: .business
            )
        }
        
        // Check for slang (especially in messaging apps)
        if appContext.appCategory == .messaging && slangPatterns.contains(lowercasedTerm) {
            return TermAnalysis(
                term: term,
                termType: .industrySlang,
                confidence: 0.9,
                likelyDomain: "internet slang",
                contextClues: ["matches messaging slang", "messaging app context"],
                needsDefinition: true,
                suggestedExplanationApproach: .urbanDictionary
            )
        }
        
        // Check for abbreviations
        if abbreviationPatterns.contains(lowercasedTerm) || isAllCaps(term) {
            return TermAnalysis(
                term: term,
                termType: .abbreviation,
                confidence: 0.75,
                likelyDomain: "general",
                contextClues: ["abbreviation pattern"],
                needsDefinition: true,
                suggestedExplanationApproach: .definition
            )
        }
        
        // Check for acronyms (all caps, pronounceable)
        if isAcronym(term) {
            return TermAnalysis(
                term: term,
                termType: .acronym,
                confidence: 0.8,
                likelyDomain: inferDomainFromContext(surroundingContext),
                contextClues: ["acronym pattern"],
                needsDefinition: true,
                suggestedExplanationApproach: .definition
            )
        }
        
        // Check for proper nouns (capitalized in middle of sentence)
        if isProperNoun(term, surroundingContext: surroundingContext) {
            return TermAnalysis(
                term: term,
                termType: .properNoun,
                confidence: 0.6,
                likelyDomain: inferDomainFromContext(surroundingContext),
                contextClues: ["capitalization pattern"],
                needsDefinition: true,
                suggestedExplanationApproach: .context
            )
        }
        
        return nil
    }
    
    private func aiPoweredAnalysis(
        term: String,
        surroundingContext: String,
        appContext: EnhancedAppContext
    ) async -> TermAnalysis {
        
        let systemPrompt = """
        You are a term classification expert. Analyze the highlighted term and classify it.
        
        Term types to consider:
        - technical_jargon: Specialized technical terminology
        - industry_slang: Casual industry-specific language
        - abbreviation: Shortened form of a word
        - acronym: Abbreviation pronounced as a word
        - foreign_word: Word from another language
        - domain_specific: Specialized vocabulary for a field
        - proper_noun: Name of specific person, place, or organization
        - general_vocabulary: Common words
        - emoji: Emoji characters
        - unknown: Cannot classify
        
        Explanation approaches:
        - first_principles: Break down to fundamental concepts
        - analogy: Use comparisons to explain
        - example: Provide concrete examples
        - definition: Direct definition
        - context: Explain based on usage context
        - urban_dictionary: Casual/slang explanation
        - technical: Technical explanation
        - business: Business-focused explanation
        - simplified: Simple, non-technical explanation
        
        Return JSON with:
        {
            "term_type": "one of the term types above",
            "confidence": 0.0-1.0,
            "likely_domain": "domain or null",
            "context_clues": ["clue1", "clue2"],
            "needs_definition": true/false,
            "explanation_approach": "one of the approaches above"
        }
        """
        
        let userPrompt = """
        Analyze this term:
        
        TERM: "\(term)"
        
        SURROUNDING CONTEXT:
        \(surroundingContext)
        
        APP CONTEXT:
        - App: \(appContext.appName)
        - Category: \(appContext.appCategory.rawValue)
        - Content Type: \(appContext.contentType.rawValue)
        
        Classify the term and suggest the best explanation approach.
        """
        
        do {
            let response = try await makeClaudeRequest(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
            
            return parseTermAnalysis(response: response, term: term)
        } catch {
            print("AI term analysis error: \(error)")
            return fallbackTermAnalysis(term: term, appContext: appContext)
        }
    }
    
    private func makeClaudeRequest(
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
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
            "max_tokens": 300,
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
    
    private func parseTermAnalysis(response: String, term: String) -> TermAnalysis {
        do {
            guard let data = response.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InferenceError.parseError("Invalid JSON")
            }
            
            let termTypeRaw = json["term_type"] as? String ?? TermType.unknown.rawValue
            let termType = TermType(rawValue: termTypeRaw) ?? .unknown
            let confidence = json["confidence"] as? Double ?? 0.5
            let likelyDomain = json["likely_domain"] as? String
            let contextClues = json["context_clues"] as? [String] ?? []
            let needsDefinition = json["needs_definition"] as? Bool ?? true
            let approachRaw = json["explanation_approach"] as? String ?? ExplanationApproach.definition.rawValue
            let explanationApproach = ExplanationApproach(rawValue: approachRaw) ?? .definition
            
            return TermAnalysis(
                term: term,
                termType: termType,
                confidence: confidence,
                likelyDomain: likelyDomain,
                contextClues: contextClues,
                needsDefinition: needsDefinition,
                suggestedExplanationApproach: explanationApproach
            )
        } catch {
            print("Parse error: \(error)")
            return TermAnalysis(
                term: term,
                termType: .unknown,
                confidence: 0.3,
                likelyDomain: nil,
                contextClues: [],
                needsDefinition: true,
                suggestedExplanationApproach: .definition
            )
        }
    }
    
    private func fallbackTermAnalysis(term: String, appContext: EnhancedAppContext) -> TermAnalysis {
        let approach: ExplanationApproach
        switch appContext.appCategory {
        case .messaging:
            approach = .urbanDictionary
        case .codeEditor:
            approach = .technical
        case .socialMedia:
            approach = .context
        default:
            approach = .definition
        }
        
        return TermAnalysis(
            term: term,
            termType: .unknown,
            confidence: 0.3,
            likelyDomain: nil,
            contextClues: ["fallback analysis"],
            needsDefinition: true,
            suggestedExplanationApproach: approach
        )
    }
    
    // Helper functions for rule-based classification
    
    private func isAllCaps(_ text: String) -> Bool {
        return text == text.uppercased() && text.count > 1 && !text.contains(" ")
    }
    
    private func isAcronym(_ text: String) -> Bool {
        let acronymPattern = "^[A-Z]{2,}$"
        return text.range(of: acronymPattern, options: .regularExpression) != nil
    }
    
    private func isProperNoun(_ term: String, surroundingContext: String) -> Bool {
        // Check if term is capitalized but not at start of sentence
        guard term.first?.isUppercase == true else { return false }
        
        // Check if it's not at the start of the surrounding context
        let contextPrefix = surroundingContext.prefix(20)
        return !contextPrefix.trimmingCharacters(in: .punctuationCharacters).isEmpty
    }
    
    private func inferDomainFromContext(_ context: String) -> String? {
        let lowercasedContext = context.lowercased()
        
        if lowercasedContext.contains("code") || lowercasedContext.contains("programming") || lowercasedContext.contains("developer") {
            return "technology"
        } else if lowercasedContext.contains("business") || lowercasedContext.contains("revenue") || lowercasedContext.contains("market") {
            return "business"
        } else if lowercasedContext.contains("medical") || lowercasedContext.contains("health") {
            return "medical"
        } else if lowercasedContext.contains("legal") || lowercasedContext.contains("law") {
            return "legal"
        }
        
        return nil
    }
}

// String extension for emoji detection
extension String {
    var containsOnlyEmoji: Bool {
        return !isEmpty && unicodeScalars.allSatisfy { $0.properties.isEmoji }
    }
}