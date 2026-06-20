import Foundation

// MARK: - User Persona Models
enum UserPersona: String, CaseIterable, Codable {
    case goToMarket = "go_to_market"
    case technical = "technical"
    case executive = "executive"
    case student = "student"
    case general = "general"
    
    var displayName: String {
        switch self {
        case .goToMarket: return "Go-to-Market"
        case .technical: return "Technical"
        case .executive: return "Executive"
        case .student: return "Student"
        case .general: return "General"
        }
    }
    
    var description: String {
        switch self {
        case .goToMarket: return "Focuses on business, sales, marketing. Non-technical background."
        case .technical: return "Engineering/development background. Understands technical concepts."
        case .executive: return "Business leadership. Focuses on strategic implications."
        case .student: return "Learning-oriented. Needs foundational explanations."
        case .general: return "Balanced generalist. Adaptable explanations."
        }
    }
    
    var knowledgeGaps: [String] {
        switch self {
        case .goToMarket: return ["technical jargon", "engineering concepts", "infrastructure terms", "developer tools"]
        case .technical: return ["business metrics", "marketing terminology", "sales processes"]
        case .executive: return ["implementation details", "technical specifics", "operational nuances"]
        case .student: return ["industry jargon", "specialized terminology", "advanced concepts"]
        case .general: return []
        }
    }
}

struct UserProfile: Codable {
    let persona: UserPersona
    let interests: [String]
    let expertiseAreas: [String]
    let learningGoals: [String]
    let preferredExplanationStyle: ExplanationStyle
    
    static let defaultProfile = UserProfile(
        persona: .general,
        interests: [],
        expertiseAreas: [],
        learningGoals: [],
        preferredExplanationStyle: .balanced
    )
}

// MARK: - Context Analysis Models
enum AppCategory: String, CaseIterable, Codable {
    case socialMedia = "social_media"
    case messaging = "messaging"
    case codeEditor = "code_editor"
    case browser = "browser"
    case document = "document"
    case email = "email"
    case notes = "notes"
    case terminal = "terminal"
    case unknown = "unknown"
    
    var typicalContentTypes: [ContentType] {
        switch self {
        case .socialMedia: return [.casual, .news, .opinion, .technical]
        case .messaging: return [.casual, .slang, .abbreviation, .personal]
        case .codeEditor: return [.technical, .code, .documentation]
        case .browser: return [.mixed, .technical, .casual, .news]
        case .document: return [.formal, .technical, .business]
        case .email: return [.formal, .business, .personal]
        case .notes: return [.mixed, .personal, .technical]
        case .terminal: return [.technical, .code]
        case .unknown: return [.mixed]
        }
    }
}

enum ContentType: String, CaseIterable, Codable {
    case technical = "technical"
    case slang = "slang"
    case abbreviation = "abbreviation"
    case formal = "formal"
    case casual = "casual"
    case business = "business"
    case code = "code"
    case documentation = "documentation"
    case news = "news"
    case opinion = "opinion"
    case personal = "personal"
    case mixed = "mixed"
}

enum TermType: String, CaseIterable, Codable {
    case technicalJargon = "technical_jargon"
    case industrySlang = "industry_slang"
    case abbreviation = "abbreviation"
    case acronym = "acronym"
    case foreignWord = "foreign_word"
    case domainSpecific = "domain_specific"
    case properNoun = "proper_noun"
    case generalVocabulary = "general_vocabulary"
    case emoji = "emoji"
    case unknown = "unknown"
}

struct EnhancedAppContext: Codable {
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let surroundingText: String?
    let appCategory: AppCategory
    let contentType: ContentType
    let screenshotData: Data?
}

// MARK: - Term Analysis Models
struct TermAnalysis: Codable {
    let term: String
    let termType: TermType
    let confidence: Double
    let likelyDomain: String?
    let contextClues: [String]
    let needsDefinition: Bool
    let suggestedExplanationApproach: ExplanationApproach
}

enum ExplanationApproach: String, CaseIterable, Codable {
    case firstPrinciples = "first_principles"
    case analogy = "analogy"
    case example = "example"
    case definition = "definition"
    case context = "context"
    case urbanDictionary = "urban_dictionary"
    case technical = "technical"
    case business = "business"
    case simplified = "simplified"
    case balanced = "balanced"
}

// MARK: - Inference Models
struct InferredQuery: Codable {
    let originalText: String
    var inferredQuestion: String
    var confidence: Double
    let reasoning: String
    var suggestedExplanationApproach: ExplanationApproach
    var alternativeQuestions: [String]
    let needsExternalLookup: Bool
    let externalLookupSource: String?
}

struct InferenceRequest: Codable {
    let highlightedText: String
    let surroundingContext: String
    let appContext: EnhancedAppContext
    let userProfile: UserProfile
}

struct InferenceResponse: Codable {
    let inferredQuery: InferredQuery
    let termAnalysis: TermAnalysis
    let contextSummary: String
    let processingTime: Double
}

// MARK: - Explanation Style Models
enum ExplanationStyle: String, CaseIterable, Codable {
    case technical = "technical"
    case simple = "simple"
    case analogy = "analogy"
    case example = "example"
    case balanced = "balanced"
    
    var systemPrompt: String {
        switch self {
        case .technical:
            return "Provide technical, detailed explanations suitable for someone with engineering background."
        case .simple:
            return "Provide simple, jargon-free explanations suitable for beginners."
        case .analogy:
            return "Use analogies and metaphors to explain concepts in relatable terms."
        case .example:
            return "Provide concrete examples to illustrate abstract concepts."
        case .balanced:
            return "Provide balanced explanations that are accessible but not oversimplified."
        }
    }
}

// MARK: - Edge Case Models
enum InferenceEdgeCase: String, CaseIterable, Codable {
    case ambiguousText = "ambiguous_text"
    case insufficientContext = "insufficient_context"
    case multipleInterpretations = "multiple_interpretations"
    case personaMismatch = "persona_mismatch"
    case unknownTerm = "unknown_term"
    case mixedContent = "mixed_content"
    case noClearIntent = "no_clear_intent"
    case privacySensitive = "privacy_sensitive"
}

struct EdgeCaseHandling: Codable {
    let edgeCase: InferenceEdgeCase
    let fallbackStrategy: FallbackStrategy
    let requiresUserConfirmation: Bool
    let alternativeSuggestions: [String]
}

enum FallbackStrategy: String, CaseIterable, Codable {
    case genericExplanation = "generic_explanation"
    case askForClarification = "ask_for_clarification"
    case provideMultipleOptions = "provide_multiple_options"
    case useSimpleDefinition = "use_simple_definition"
    case skipInference = "skip_inference"
    case requestMoreContext = "request_more_context"
}