import Foundation

class EdgeCaseHandler {
    
    func detectEdgeCases(
        highlightedText: String,
        surroundingContext: String,
        appContext: EnhancedAppContext,
        termAnalysis: TermAnalysis,
        userProfile: UserProfile
    ) -> [EdgeCaseHandling] {
        
        var edgeCases: [EdgeCaseHandling] = []
        
        // Check for ambiguous text
        if isAmbiguousText(highlightedText, surroundingContext: surroundingContext) {
            edgeCases.append(EdgeCaseHandling(
                edgeCase: .ambiguousText,
                fallbackStrategy: .provideMultipleOptions,
                requiresUserConfirmation: true,
                alternativeSuggestions: generateAmbiguityAlternatives(highlightedText)
            ))
        }
        
        // Check for insufficient context
        if isInsufficientContext(surroundingContext) {
            edgeCases.append(EdgeCaseHandling(
                edgeCase: .insufficientContext,
                fallbackStrategy: .useSimpleDefinition,
                requiresUserConfirmation: false,
                alternativeSuggestions: ["Provide more context for better explanation"]
            ))
        }
        
        // Check for multiple interpretations
        if hasMultipleInterpretations(highlightedText, termAnalysis: termAnalysis) {
            edgeCases.append(EdgeCaseHandling(
                edgeCase: .multipleInterpretations,
                fallbackStrategy: .provideMultipleOptions,
                requiresUserConfirmation: true,
                alternativeSuggestions: generateInterpretationAlternatives(highlightedText, termAnalysis: termAnalysis)
            ))
        }
        
        // Check for persona mismatch
        if hasPersonaMismatch(termAnalysis: termAnalysis, userProfile: userProfile) {
            edgeCases.append(EdgeCaseHandling(
                edgeCase: .personaMismatch,
                fallbackStrategy: .genericExplanation,
                requiresUserConfirmation: false,
                alternativeSuggestions: adjustForPersona(highlightedText, userProfile: userProfile)
            ))
        }
        
        // Check for unknown terms
        if termAnalysis.termType == .unknown && termAnalysis.confidence < 0.4 {
            edgeCases.append(EdgeCaseHandling(
                edgeCase: .unknownTerm,
                fallbackStrategy: .askForClarification,
                requiresUserConfirmation: true,
                alternativeSuggestions: ["What type of explanation would you prefer?"]
            ))
        }
        
        // Check for mixed content
        if appContext.contentType == .mixed {
            edgeCases.append(EdgeCaseHandling(
                edgeCase: .mixedContent,
                fallbackStrategy: .provideMultipleOptions,
                requiresUserConfirmation: false,
                alternativeSuggestions: generateMixedContentAlternatives(highlightedText)
            ))
        }
        
        // Check for no clear intent
        if hasNoClearIntent(highlightedText, surroundingContext: surroundingContext) {
            edgeCases.append(EdgeCaseHandling(
                edgeCase: .noClearIntent,
                fallbackStrategy: .askForClarification,
                requiresUserConfirmation: true,
                alternativeSuggestions: [
                    "What would you like to know about this?",
                    "Are you looking for a definition or context?"
                ]
            ))
        }
        
        // Check for privacy-sensitive content
        if containsPrivacySensitiveContent(highlightedText, surroundingContext: surroundingContext) {
            edgeCases.append(EdgeCaseHandling(
                edgeCase: .privacySensitive,
                fallbackStrategy: .skipInference,
                requiresUserConfirmation: true,
                alternativeSuggestions: [
                    "This appears to contain sensitive information",
                    "Please highlight non-sensitive text"
                ]
            ))
        }
        
        return edgeCases
    }
    
    // MARK: - Edge Case Detection Methods
    
    private func isAmbiguousText(_ text: String, surroundingContext: String) -> Bool {
        // Check if text has multiple possible meanings
        let ambiguousTerms = ["bank", "bat", "bow", "date", "fine", "lead", "match", "mean", "park", "right", "run", "table", "well"]
        let lowercasedText = text.lowercased()
        
        if ambiguousTerms.contains(lowercasedText) {
            // Check if context provides disambiguation
            let contextLower = surroundingContext.lowercased()
            let hasDisambiguatingContext = contextLower.contains("money") || contextLower.contains("river") ||
                                         contextLower.contains("baseball") || contextLower.contains("animal")
            
            return !hasDisambiguatingContext
        }
        
        // Check for short, common words
        if text.count <= 3 && text.range(of: "^[a-z]+$", options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    private func isInsufficientContext(_ context: String) -> Bool {
        // Check if context is too short or lacks helpful information
        let wordCount = context.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return wordCount < 5
    }
    
    private func hasMultipleInterpretations(_ text: String, termAnalysis: TermAnalysis) -> Bool {
        // Check if term analysis suggests multiple possible interpretations
        if termAnalysis.confidence < 0.6 {
            return true
        }
        
        // Check for terms that commonly have multiple meanings
        let multiMeaningTerms = ["cloud", "server", "client", "service", "platform", "system"]
        let lowercasedText = text.lowercased()
        
        return multiMeaningTerms.contains(lowercasedText)
    }
    
    private func hasPersonaMismatch(termAnalysis: TermAnalysis, userProfile: UserProfile) -> Bool {
        // Check if term type doesn't match persona's expertise
        switch userProfile.persona {
        case .goToMarket:
            return termAnalysis.termType == .technicalJargon
        case .technical:
            return termAnalysis.termType == .domainSpecific && termAnalysis.likelyDomain == "business"
        case .executive:
            return termAnalysis.termType == .technicalJargon
        case .student:
            return termAnalysis.termType == .domainSpecific
        case .general:
            return false
        }
    }
    
    private func hasNoClearIntent(_ text: String, surroundingContext: String) -> Bool {
        // Check if highlighted text doesn't seem to be something needing explanation
        if text.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        
        // Check for common words that rarely need explanation
        let commonWords = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"]
        let lowercasedText = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        
        if commonWords.contains(lowercasedText) {
            return true
        }
        
        // Check if text is just a number or single character
        if text.count == 1 || text.range(of: "^\\d+$", options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    private func containsPrivacySensitiveContent(_ text: String, surroundingContext: String) -> Bool {
        let combinedText = (text + " " + surroundingContext).lowercased()
        
        // Check for common sensitive patterns
        let sensitivePatterns = [
            "password", "ssn", "social security", "credit card", "api key", "secret",
            "token", "private key", "authentication", "confidential", "personal"
        ]
        
        return sensitivePatterns.contains { combinedText.contains($0) }
    }
    
    // MARK: - Alternative Suggestion Generators
    
    private func generateAmbiguityAlternatives(_ text: String) -> [String] {
        return [
            "What does '\(text)' mean in this context?",
            "Define '\(text)' and explain its different meanings",
            "How is '\(text)' being used here?"
        ]
    }
    
    private func generateInterpretationAlternatives(_ text: String, termAnalysis: TermAnalysis) -> [String] {
        var alternatives: [String] = []
        
        switch termAnalysis.termType {
        case .technicalJargon:
            alternatives = [
                "What is the technical definition of '\(text)'?",
                "Explain '\(text)' in business terms",
                "What does '\(text)' mean in this context?"
            ]
        case .domainSpecific:
            alternatives = [
                "What does '\(text)' mean in \(termAnalysis.likelyDomain ?? "this field")?",
                "Explain '\(text)' for a general audience",
                "Why is '\(text)' important here?"
            ]
        default:
            alternatives = [
                "What does '\(text)' mean?",
                "How should I understand '\(text)' in this context?",
                "Define '\(text)' from first principles"
            ]
        }
        
        return alternatives
    }
    
    private func adjustForPersona(_ text: String, userProfile: UserProfile) -> [String] {
        switch userProfile.persona {
        case .goToMarket:
            return [
                "What does '\(text)' mean for our business?",
                "Why should I care about '\(text)'?",
                "Explain '\(text)' in business terms"
            ]
        case .technical:
            return [
                "How is '\(text)' implemented?",
                "What are the technical implications of '\(text)'?",
                "Explain the architecture behind '\(text)'"
            ]
        case .executive:
            return [
                "What are the strategic implications of '\(text)'?",
                "How does '\(text)' impact our business?",
                "What's the ROI of '\(text)'?"
            ]
        case .student:
            return [
                "Can you explain '\(text)' simply?",
                "What's a good analogy for '\(text)'?",
                "Why is '\(text)' important to learn?"
            ]
        case .general:
            return [
                "What does '\(text)' mean?",
                "How would you explain '\(text)' to anyone?",
                "Why does '\(text)' matter?"
            ]
        }
    }
    
    private func generateMixedContentAlternatives(_ text: String) -> [String] {
        return [
            "What does '\(text)' mean in this context?",
            "Is '\(text)' being used technically or casually?",
            "Explain '\(text)' from different perspectives"
        ]
    }
    
    // MARK: - Edge Case Resolution
    
    func resolveEdgeCases(
        edgeCases: [EdgeCaseHandling],
        originalQuery: InferredQuery
    ) -> InferredQuery {
        
        guard let primaryEdgeCase = edgeCases.first else {
            return originalQuery
        }
        
        var modifiedQuery = originalQuery
        
        switch primaryEdgeCase.fallbackStrategy {
        case .genericExplanation:
            modifiedQuery.inferredQuestion = "What does '\(originalQuery.originalText)' mean?"
            modifiedQuery.confidence = max(0.3, originalQuery.confidence - 0.2)
            
        case .askForClarification:
            modifiedQuery.inferredQuestion = "What would you like to know about '\(originalQuery.originalText)'?"
            modifiedQuery.confidence = 0.2
            
        case .provideMultipleOptions:
            modifiedQuery.alternativeQuestions = primaryEdgeCase.alternativeSuggestions
            modifiedQuery.inferredQuestion = primaryEdgeCase.alternativeSuggestions.first ?? originalQuery.inferredQuestion
            modifiedQuery.confidence = max(0.4, originalQuery.confidence - 0.1)
            
        case .useSimpleDefinition:
            modifiedQuery.inferredQuestion = "Define '\(originalQuery.originalText)' simply"
            modifiedQuery.suggestedExplanationApproach = .simplified
            modifiedQuery.confidence = max(0.5, originalQuery.confidence - 0.1)
            
        case .skipInference:
            modifiedQuery.inferredQuestion = ""
            modifiedQuery.confidence = 0.0
            
        case .requestMoreContext:
            modifiedQuery.inferredQuestion = "Please provide more context about '\(originalQuery.originalText)'"
            modifiedQuery.confidence = 0.1
        }
        
        return modifiedQuery
    }
    
    // MARK: - Privacy and Safety
    
    func shouldProcessRequest(highlightedText: String, surroundingContext: String) -> Bool {
        let edgeCases = detectEdgeCases(
            highlightedText: highlightedText,
            surroundingContext: surroundingContext,
            appContext: EnhancedAppContext(
                appName: "unknown",
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: highlightedText,
                surroundingText: surroundingContext,
                appCategory: .unknown,
                contentType: .mixed,
                screenshotData: nil
            ),
            termAnalysis: TermAnalysis(
                term: highlightedText,
                termType: .unknown,
                confidence: 0.5,
                likelyDomain: nil,
                contextClues: [],
                needsDefinition: true,
                suggestedExplanationApproach: .definition
            ),
            userProfile: .defaultProfile
        )
        
        // Check if privacy-sensitive edge case is present
        if edgeCases.contains(where: { $0.edgeCase == .privacySensitive }) {
            return false
        }
        
        return true
    }
}