import Foundation

class PersonaConfiguration {
    
    // Pre-configured persona profiles
    static let personas: [UserPersona: PersonaProfile] = [
        .goToMarket: PersonaProfile(
            persona: .goToMarket,
            name: "Go-to-Market Professional",
            description: "Focuses on business strategy, sales, marketing, and customer success. Needs technical concepts explained in business terms.",
            knowledgeGaps: [
                "technical jargon",
                "engineering concepts",
                "infrastructure terminology",
                "developer tools",
                "implementation details"
            ],
            typicalQuestions: [
                "What does this mean for our business?",
                "Why should customers care about this?",
                "How does this impact our market position?",
                "What's the business value?",
                "How would I explain this to a prospect?"
            ],
            preferredExplanationApproaches: [
                .business,
                .analogy,
                .example
            ],
            appSpecificBehaviors: [
                .socialMedia: "Focus on business implications and market impact",
                .messaging: "Consider casual business context",
                .codeEditor: "Skip technical details, focus on business value"
            ]
        ),
        
        .technical: PersonaProfile(
            persona: .technical,
            name: "Technical Professional",
            description: "Engineering/development background. Understands technical concepts but may need business context or implementation details.",
            knowledgeGaps: [
                "business metrics",
                "marketing terminology",
                "sales processes",
                "strategic frameworks"
            ],
            typicalQuestions: [
                "How is this implemented?",
                "What are the technical tradeoffs?",
                "How does this integrate with existing systems?",
                "What's the architecture behind this?",
                "Are there any performance implications?"
            ],
            preferredExplanationApproaches: [
                .technical,
                .firstPrinciples,
                .example
            ],
            appSpecificBehaviors: [
                .codeEditor: "Focus on implementation details and code patterns",
                .browser: "Balance technical accuracy with context",
                .document: "Provide technical specifications"
            ]
        ),
        
        .executive: PersonaProfile(
            persona: .executive,
            name: "Executive Leader",
            description: "Business leadership focused on strategic implications, ROI, and high-level impact. Needs concise, strategic explanations.",
            knowledgeGaps: [
                "implementation details",
                "technical specifics",
                "operational nuances",
                "low-level mechanics"
            ],
            typicalQuestions: [
                "What are the strategic implications?",
                "What's the ROI?",
                "How does this impact our competitive position?",
                "What are the risks and opportunities?",
                "How does this align with our goals?"
            ],
            preferredExplanationApproaches: [
                .business,
                .context,
                .simplified
            ],
            appSpecificBehaviors: [
                .socialMedia: "Focus on market trends and competitive insights",
                .email: "Consider strategic business context",
                .document: "Extract key strategic points"
            ]
        ),
        
        .student: PersonaProfile(
            persona: .student,
            name: "Student/Learner",
            description: "Learning-oriented with foundational knowledge. Needs explanations built from first principles with examples and analogies.",
            knowledgeGaps: [
                "industry jargon",
                "specialized terminology",
                "advanced concepts",
                "context-specific knowledge"
            ],
            typicalQuestions: [
                "Can you explain this simply?",
                "What's a good analogy for this?",
                "Why is this important to learn?",
                "How does this connect to what I already know?",
                "What are the prerequisites for understanding this?"
            ],
            preferredExplanationApproaches: [
                .simplified,
                .analogy,
                .example,
                .firstPrinciples
            ],
            appSpecificBehaviors: [
                .browser: "Provide educational context and links",
                .document: "Break down complex concepts",
                .notes: "Support learning and retention"
            ]
        ),
        
        .general: PersonaProfile(
            persona: .general,
            name: "General User",
            description: "Balanced generalist with adaptable learning style. Needs clear, context-appropriate explanations.",
            knowledgeGaps: [],
            typicalQuestions: [
                "What does this mean?",
                "How would you explain this to anyone?",
                "Why does this matter?",
                "What's the context here?"
            ],
            preferredExplanationApproaches: [
                .definition,
                .context,
                .analogy
            ],
            appSpecificBehaviors: [
                .socialMedia: "Consider casual vs formal context",
                .messaging: "Adapt to conversation tone",
                .browser: "Provide balanced explanation"
            ]
        )
    ]
    
    static func getPersonaProfile(for persona: UserPersona) -> PersonaProfile? {
        return personas[persona]
    }
    
    static func getRecommendedPersona(for userDescription: String) -> UserPersona {
        let lowercasedDescription = userDescription.lowercased()
        
        if lowercasedDescription.contains("marketing") || lowercasedDescription.contains("sales") ||
           lowercasedDescription.contains("business") || lowercasedDescription.contains("gtm") {
            return .goToMarket
        } else if lowercasedDescription.contains("engineer") || lowercasedDescription.contains("developer") ||
                  lowercasedDescription.contains("technical") || lowercasedDescription.contains("programming") {
            return .technical
        } else if lowercasedDescription.contains("executive") || lowercasedDescription.contains("ceo") ||
                  lowercasedDescription.contains("leadership") || lowercasedDescription.contains("strategy") {
            return .executive
        } else if lowercasedDescription.contains("student") || lowercasedDescription.contains("learning") ||
                  lowercasedDescription.contains("education") {
            return .student
        } else {
            return .general
        }
    }
}

struct PersonaProfile {
    let persona: UserPersona
    let name: String
    let description: String
    let knowledgeGaps: [String]
    let typicalQuestions: [String]
    let preferredExplanationApproaches: [ExplanationApproach]
    let appSpecificBehaviors: [AppCategory: String]
}

// MARK: - App Configuration

class AppConfiguration {
    static let appCategories: [String: AppCategory] = [
        // Social Media
        "twitter": .socialMedia,
        "x": .socialMedia,
        "facebook": .socialMedia,
        "instagram": .socialMedia,
        "linkedin": .socialMedia,
        "reddit": .socialMedia,
        
        // Messaging
        "messages": .messaging,
        "imessage": .messaging,
        "whatsapp": .messaging,
        "telegram": .messaging,
        "discord": .messaging,
        "slack": .messaging,
        
        // Code Editors
        "vscode": .codeEditor,
        "intellij": .codeEditor,
        "xcode": .codeEditor,
        "sublime": .codeEditor,
        "vim": .codeEditor,
        "emacs": .codeEditor,
        
        // Browsers
        "chrome": .browser,
        "safari": .browser,
        "firefox": .browser,
        "edge": .browser,
        "brave": .browser,
        
        // Documents
        "word": .document,
        "pages": .document,
        "pdf": .document,
        
        // Email
        "mail": .email,
        "outlook": .email,
        "gmail": .email,
        
        // Notes
        "notes": .notes,
        "notion": .notes,
        "evernote": .notes
    ]
    
    static func getAppCategory(for appName: String) -> AppCategory {
        let lowerAppName = appName.lowercased()
        
        for (key, category) in appCategories {
            if lowerAppName.contains(key) {
                return category
            }
        }
        
        return .unknown
    }
}

// MARK: - Inference Configuration

class InferenceConfiguration {
    static let shared = InferenceConfiguration()
    
    var confidenceThreshold: Double = 0.5
    var enableEdgeCaseDetection: Bool = true
    var enablePrivacyChecks: Bool = true
    var maxContextLength: Int = 500
    var defaultPersona: UserPersona = .general
    var cacheEnabled: Bool = true
    var cacheExpirationHours: Int = 24
    
    private init() {}
    
    func updateConfiguration(
        confidenceThreshold: Double? = nil,
        enableEdgeCaseDetection: Bool? = nil,
        enablePrivacyChecks: Bool? = nil,
        maxContextLength: Int? = nil,
        defaultPersona: UserPersona? = nil,
        cacheEnabled: Bool? = nil,
        cacheExpirationHours: Int? = nil
    ) {
        if let confidenceThreshold = confidenceThreshold {
            self.confidenceThreshold = confidenceThreshold
        }
        if let enableEdgeCaseDetection = enableEdgeCaseDetection {
            self.enableEdgeCaseDetection = enableEdgeCaseDetection
        }
        if let enablePrivacyChecks = enablePrivacyChecks {
            self.enablePrivacyChecks = enablePrivacyChecks
        }
        if let maxContextLength = maxContextLength {
            self.maxContextLength = maxContextLength
        }
        if let defaultPersona = defaultPersona {
            self.defaultPersona = defaultPersona
        }
        if let cacheEnabled = cacheEnabled {
            self.cacheEnabled = cacheEnabled
        }
        if let cacheExpirationHours = cacheExpirationHours {
            self.cacheExpirationHours = cacheExpirationHours
        }
    }
}