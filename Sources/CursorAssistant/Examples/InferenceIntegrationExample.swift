import Foundation

// This file demonstrates how to integrate the new inference backend with the existing CursorAssistant system

class EnhancedCursorAssistant {
    private let inferenceOrchestrator: InferenceOrchestrator
    private let existingContextService: ContextInferenceService
    private let claudeService: ClaudeAIService
    private let userProfileManager: UserProfileManager
    
    init(apiKey: String) {
        self.inferenceOrchestrator = InferenceOrchestrator(apiKey: apiKey)
        self.existingContextService = ContextInferenceService(apiKey: apiKey)
        self.claudeService = ClaudeAIService(apiKey: apiKey)
        self.userProfileManager = UserProfileManager()
    }
    
    // Enhanced version of existing text selection handling
    func handleTextSelection(selectedText: String) async -> String {
        // Step 1: Collect context using existing service
        let appContext = existingContextService.collectContext()
        
        // Step 2: Privacy check
        guard inferenceOrchestrator.shouldProcessInference(
            highlightedText: selectedText,
            surroundingContext: appContext.surroundingText ?? ""
        ) else {
            return "This appears to contain sensitive information. Please highlight non-sensitive text."
        }
        
        // Step 3: Infer user's intended question
        let inferenceResponse = await inferenceOrchestrator.inferUserQuery(
            highlightedText: selectedText,
            surroundingContext: appContext.surroundingText ?? "",
            appName: appContext.appName,
            bundleIdentifier: appContext.bundleIdentifier,
            windowTitle: appContext.windowTitle,
            screenshotData: appContext.screenshotData
        )
        
        // Step 4: Get explanation using the inferred question
        let explanation = await getExplanation(
            term: selectedText,
            inferredQuestion: inferenceResponse.inferredQuery.inferredQuestion,
            approach: inferenceResponse.inferredQuery.suggestedExplanationApproach,
            context: appContext.surroundingText ?? ""
        )
        
        return explanation
    }
    
    private func getExplanation(
        term: String,
        inferredQuestion: String,
        approach: ExplanationApproach,
        context: String
    ) async -> String {
        
        let systemPrompt = buildSystemPrompt(for: approach)
        let userPrompt = """
        Question: \(inferredQuestion)
        
        Term: "\(term)"
        
        Context: \(context)
        
        Provide a clear, concise explanation (2-3 sentences max).
        """
        
        // Use existing Claude service or direct API call
        // This would integrate with your existing ClaudeAIService
        // For now, return a placeholder
        return "Explanation based on: \(inferredQuestion)"
    }
    
    private func buildSystemPrompt(for approach: ExplanationApproach) -> String {
        switch approach {
        case .firstPrinciples:
            return "Explain by breaking down the concept to its fundamental principles. Build up understanding from basic concepts."
        case .analogy:
            return "Use relatable analogies and metaphors to explain the concept. Compare it to everyday experiences."
        case .example:
            return "Provide concrete examples to illustrate the concept. Show how it works in practice."
        case .definition:
            return "Provide a clear, direct definition of the term. Include key characteristics."
        case .context:
            return "Explain the term based on how it's being used in this specific context. Focus on contextual meaning."
        case .urbanDictionary:
            return "Explain the slang or casual meaning of the term. Use informal, conversational language."
        case .technical:
            return "Provide a technical explanation suitable for someone with engineering background. Include implementation details where relevant."
        case .business:
            return "Explain the business implications and value. Focus on impact, ROI, and strategic importance."
        case .simplified:
            return "Explain in simple, jargon-free language suitable for beginners. Avoid technical complexity."
        case .balanced:
            return "Provide a balanced explanation that is accessible but not oversimplified."
        }
    }
}

// MARK: - Real-World Usage Scenarios

class ScenarioExamples {
    
    // Scenario 1: Go-to-Market persona reading technical content on Twitter
    func scenario1_GTM_Twitter_Technical() async {
        let assistant = EnhancedCursorAssistant(apiKey: "your-api-key")
        
        // Set persona
        let profileManager = UserProfileManager()
        profileManager.updatePersona(.goToMarket)
        
        // Simulate highlighting technical term on Twitter
        let explanation = await assistant.handleTextSelection(
            selectedText: "agent cloud"
        )
        
        print("Explanation: \(explanation)")
        // Expected: Business-focused explanation of agent cloud thesis
    }
    
    // Scenario 2: General user encountering slang in iMessage
    func scenario2_IMessage_Slang() async {
        let assistant = EnhancedCursorAssistant(apiKey: "your-api-key")
        
        // Simulate highlighting slang in Messages
        let explanation = await assistant.handleTextSelection(
            selectedText: "ghost"
        )
        
        print("Explanation: \(explanation)")
        // Expected: Urban dictionary-style explanation of ghosting
    }
    
    // Scenario 3: Technical person in VS Code
    func scenario3_Technical_VSCode() async {
        let assistant = EnhancedCursorAssistant(apiKey: "your-api-key")
        
        // Set technical persona
        let profileManager = UserProfileManager()
        profileManager.updatePersona(.technical)
        
        // Simulate highlighting technical term in code
        let explanation = await assistant.handleTextSelection(
            selectedText: "GraphQL"
        )
        
        print("Explanation: \(explanation)")
        // Expected: Technical explanation with implementation details
    }
    
    // Scenario 4: Student learning new concept
    func scenario4_Student_Browser() async {
        let assistant = EnhancedCursorAssistant(apiKey: "your-api-key")
        
        // Set student persona
        let profileManager = UserProfileManager()
        profileManager.updatePersona(.student)
        
        // Simulate highlighting concept in browser
        let explanation = await assistant.handleTextSelection(
            selectedText: "blockchain"
        )
        
        print("Explanation: \(explanation)")
        // Expected: Simple explanation with analogies and examples
    }
    
    // Scenario 5: Executive reading business document
    func scenario5_Executive_Document() async {
        let assistant = EnhancedCursorAssistant(apiKey: "your-api-key")
        
        // Set executive persona
        let profileManager = UserProfileManager()
        profileManager.updatePersona(.executive)
        
        // Simulate highlighting term in document
        let explanation = await assistant.handleTextSelection(
            selectedText: "EBITDA"
        )
        
        print("Explanation: \(explanation)")
        // Expected: Strategic explanation focusing on business implications
    }
}

// MARK: - Setup and Configuration

class InferenceSetup {
    
    static func setupDefaultConfiguration() {
        let config = InferenceConfiguration.shared
        
        // Recommended settings for production
        config.updateConfiguration(
            confidenceThreshold: 0.5,
            enableEdgeCaseDetection: true,
            enablePrivacyChecks: true,
            maxContextLength: 500,
            defaultPersona: .general,
            cacheEnabled: true,
            cacheExpirationHours: 24
        )
    }
    
    static func setupForPowerUser() {
        let config = InferenceConfiguration.shared
        
        // Settings for users who want more accurate but slower inference
        config.updateConfiguration(
            confidenceThreshold: 0.7,
            enableEdgeCaseDetection: true,
            enablePrivacyChecks: true,
            maxContextLength: 1000,
            defaultPersona: .general,
            cacheEnabled: true,
            cacheExpirationHours: 48
        )
    }
    
    static func setupForRealTime() {
        let config = InferenceConfiguration.shared
        
        // Settings for real-time performance
        config.updateConfiguration(
            confidenceThreshold: 0.4,
            enableEdgeCaseDetection: false,
            enablePrivacyChecks: true,
            maxContextLength: 200,
            defaultPersona: .general,
            cacheEnabled: true,
            cacheExpirationHours: 12
        )
    }
    
    static func setupPersonaBasedOnUserSurvey() {
        let profileManager = UserProfileManager()
        
        // Example: Based on user survey responses
        let userResponses = [
            "I work in marketing",
            "I don't have technical background",
            "I care about business metrics"
        ]
        
        let combinedResponses = userResponses.joined(separator: " ")
        let recommendedPersona = PersonaConfiguration.getRecommendedPersona(
            for: combinedResponses
        )
        
        profileManager.updatePersona(recommendedPersona)
        
        // Set explanation style based on persona
        switch recommendedPersona {
        case .goToMarket:
            profileManager.updateExplanationStyle(.analogy)
        case .technical:
            profileManager.updateExplanationStyle(.technical)
        case .executive:
            profileManager.updateExplanationStyle(.simple)
        case .student:
            profileManager.updateExplanationStyle(.analogy)
        case .general:
            profileManager.updateExplanationStyle(.balanced)
        }
    }
}

// MARK: - Testing and Validation

class InferenceTesting {
    
    func testInferenceAccuracy() async {
        let orchestrator = InferenceOrchestrator(apiKey: "your-api-key")
        
        let testCases = [
            (
                highlightedText: "SaaS",
                context: "Our SaaS platform serves enterprise clients",
                appName: "Twitter",
                expectedQuestion: "What does SaaS mean in a business context?"
            ),
            (
                highlightedText: "ghost",
                context: "I can't believe he ghosted me",
                appName: "Messages",
                expectedQuestion: "What does ghost mean in this conversation?"
            ),
            (
                highlightedText: "API",
                context: "The API provides data access",
                appName: "VS Code",
                expectedQuestion: "How is the API implemented?"
            )
        ]
        
        for testCase in testCases {
            let response = await orchestrator.quickInfer(
                highlightedText: testCase.highlightedText,
                surroundingContext: testCase.context,
                appName: testCase.appName
            )
            
            print("Test: \(testCase.highlightedText)")
            print("Expected: \(testCase.expectedQuestion)")
            print("Actual: \(response)")
            print("---")
        }
    }
    
    func testEdgeCases() async {
        let orchestrator = InferenceOrchestrator(apiKey: "your-api-key")
        
        // Test privacy-sensitive content
        let shouldProcess = orchestrator.shouldProcessInference(
            highlightedText: "password",
            surroundingContext: "My password is secret123"
        )
        
        print("Privacy test should process: \(shouldProcess)") // Should be false
        
        // Test ambiguous text
        let response = await orchestrator.quickInfer(
            highlightedText: "bank",
            surroundingContext: "I went to the",
            appName: "Messages"
        )
        
        print("Ambiguous text response: \(response)")
    }
}

// MARK: - Migration Guide

/*
MIGRATION GUIDE: Integrating New Inference Backend

1. Replace existing ContextInferenceService with enhanced version:
   - Keep existing context collection logic
   - Add inference orchestrator integration
   - Update persona management

2. Update existing ClaudeAIService calls:
   - Use inferred questions instead of generic prompts
   - Apply explanation approach based on term analysis
   - Use persona-specific system prompts

3. Add user profile setup:
   - Run initial persona detection
   - Provide UI for persona selection
   - Allow profile customization

4. Update caching strategy:
   - Cache inferred queries
   - Store term analysis results
   - Implement cache invalidation

5. Add error handling:
   - Handle edge cases gracefully
   - Provide fallback explanations
   - Log inference failures

6. Testing:
   - Test with different personas
   - Validate edge case handling
   - Measure performance impact
*/