import Foundation

class InferenceOrchestrator {
    private let apiKey: String
    private let queryGenerator: PersonaAwareQueryGenerator
    private let termAnalyzer: TermAnalyzer
    private let edgeCaseHandler: EdgeCaseHandler
    private let contextAnalyzer: EnhancedContextAnalyzer
    private let userProfileManager: UserProfileManager
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.queryGenerator = PersonaAwareQueryGenerator(apiKey: apiKey)
        self.termAnalyzer = TermAnalyzer(apiKey: apiKey)
        self.edgeCaseHandler = EdgeCaseHandler()
        self.contextAnalyzer = EnhancedContextAnalyzer()
        self.userProfileManager = UserProfileManager()
    }
    
    // Main inference function - coordinates all components
    func inferUserQuery(
        highlightedText: String,
        surroundingContext: String,
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?,
        screenshotData: Data? = nil
    ) async -> InferenceResponse {
        
        let startTime = Date()
        
        // Step 1: Build enhanced app context
        let appContext = contextAnalyzer.buildEnhancedAppContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: highlightedText,
            surroundingText: surroundingContext,
            screenshotData: screenshotData
        )
        
        // Step 2: Get user profile
        let userProfile = userProfileManager.getCurrentProfile()
        
        // Step 3: Analyze the highlighted term
        let termAnalysis = await termAnalyzer.analyzeTerm(
            term: highlightedText,
            surroundingContext: surroundingContext,
            appContext: appContext
        )
        
        // Step 4: Generate persona-aware query
        var inferredQuery = await queryGenerator.generateInferredQuery(
            highlightedText: highlightedText,
            surroundingContext: surroundingContext,
            appContext: appContext,
            userProfile: userProfile
        )
        
        // Step 5: Detect and handle edge cases
        let edgeCases = edgeCaseHandler.detectEdgeCases(
            highlightedText: highlightedText,
            surroundingContext: surroundingContext,
            appContext: appContext,
            termAnalysis: termAnalysis,
            userProfile: userProfile
        )
        
        // Step 6: Apply edge case resolutions if needed
        if !edgeCases.isEmpty {
            inferredQuery = edgeCaseHandler.resolveEdgeCases(
                edgeCases: edgeCases,
                originalQuery: inferredQuery
            )
        }
        
        // Step 7: Generate context summary
        let contextSummary = generateContextSummary(
            appContext: appContext,
            termAnalysis: termAnalysis,
            userProfile: userProfile
        )
        
        // Step 8: Calculate processing time
        let processingTime = Date().timeIntervalSince(startTime)
        
        return InferenceResponse(
            inferredQuery: inferredQuery,
            termAnalysis: termAnalysis,
            contextSummary: contextSummary,
            processingTime: processingTime
        )
    }
    
    // Simplified inference function for quick responses
    func quickInfer(
        highlightedText: String,
        surroundingContext: String,
        appName: String
    ) async -> String {
        
        let appCategory = contextAnalyzer.analyzeAppContext(
            bundleIdentifier: nil,
            appName: appName
        )
        
        let contentType = contextAnalyzer.classifyContentType(
            surroundingText: surroundingContext,
            appCategory: appCategory,
            windowTitle: nil
        )
        
        let appContext = EnhancedAppContext(
            appName: appName,
            bundleIdentifier: nil,
            windowTitle: nil,
            selectedText: highlightedText,
            surroundingText: surroundingContext,
            appCategory: appCategory,
            contentType: contentType,
            screenshotData: nil
        )
        
        let userProfile = userProfileManager.getCurrentProfile()
        
        let inferredQuery = await queryGenerator.generateInferredQuery(
            highlightedText: highlightedText,
            surroundingContext: surroundingContext,
            appContext: appContext,
            userProfile: userProfile
        )
        
        return inferredQuery.inferredQuestion
    }
    
    // Privacy check before processing
    func shouldProcessInference(
        highlightedText: String,
        surroundingContext: String
    ) -> Bool {
        return edgeCaseHandler.shouldProcessRequest(
            highlightedText: highlightedText,
            surroundingContext: surroundingContext
        )
    }
    
    // Generate a human-readable context summary
    private func generateContextSummary(
        appContext: EnhancedAppContext,
        termAnalysis: TermAnalysis,
        userProfile: UserProfile
    ) -> String {
        var summary = "User is highlighting '\(appContext.selectedText ?? "")' in \(appContext.appName). "
        summary += "Detected as \(termAnalysis.termType.rawValue) with \(termAnalysis.confidence * 100)% confidence. "
        summary += "User persona: \(userProfile.persona.displayName). "
        
        if let domain = termAnalysis.likelyDomain {
            summary += "Domain: \(domain). "
        }
        
        summary += "Content type: \(appContext.contentType.rawValue)."
        
        return summary
    }
    
    // Batch inference for multiple terms
    func batchInfer(
        terms: [(text: String, context: String, appName: String)]
    ) async -> [InferenceResponse] {
        
        var responses: [InferenceResponse] = []
        
        for term in terms {
            let response = await inferUserQuery(
                highlightedText: term.text,
                surroundingContext: term.context,
                appName: term.appName,
                bundleIdentifier: nil,
                windowTitle: nil,
                screenshotData: nil
            )
            responses.append(response)
        }
        
        return responses
    }
}

// MARK: - User Profile Manager

class UserProfileManager {
    private let userDefaultsKey = "user_profile"
    
    func getCurrentProfile() -> UserProfile {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            return profile
        }
        return .defaultProfile
    }
    
    func saveProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    func updatePersona(_ persona: UserPersona) {
        var currentProfile = getCurrentProfile()
        currentProfile = UserProfile(
            persona: persona,
            interests: currentProfile.interests,
            expertiseAreas: currentProfile.expertiseAreas,
            learningGoals: currentProfile.learningGoals,
            preferredExplanationStyle: currentProfile.preferredExplanationStyle
        )
        saveProfile(currentProfile)
    }
    
    func updateExplanationStyle(_ style: ExplanationStyle) {
        var currentProfile = getCurrentProfile()
        currentProfile = UserProfile(
            persona: currentProfile.persona,
            interests: currentProfile.interests,
            expertiseAreas: currentProfile.expertiseAreas,
            learningGoals: currentProfile.learningGoals,
            preferredExplanationStyle: style
        )
        saveProfile(currentProfile)
    }
    
    func addInterest(_ interest: String) {
        var currentProfile = getCurrentProfile()
        var interests = currentProfile.interests
        if !interests.contains(interest) {
            interests.append(interest)
        }
        currentProfile = UserProfile(
            persona: currentProfile.persona,
            interests: interests,
            expertiseAreas: currentProfile.expertiseAreas,
            learningGoals: currentProfile.learningGoals,
            preferredExplanationStyle: currentProfile.preferredExplanationStyle
        )
        saveProfile(currentProfile)
    }
    
    func addExpertiseArea(_ area: String) {
        var currentProfile = getCurrentProfile()
        var expertise = currentProfile.expertiseAreas
        if !expertise.contains(area) {
            expertise.append(area)
        }
        currentProfile = UserProfile(
            persona: currentProfile.persona,
            interests: currentProfile.interests,
            expertiseAreas: expertise,
            learningGoals: currentProfile.learningGoals,
            preferredExplanationStyle: currentProfile.preferredExplanationStyle
        )
        saveProfile(currentProfile)
    }
}