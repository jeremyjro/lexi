import Foundation

enum LearningStyle: String, CaseIterable, Codable {
    case analogies = "analogies"
    case examples = "examples"
    case technical = "technical"
    case simple = "simple"
    case visual = "visual"
    
    var displayName: String {
        switch self {
        case .analogies: return "Analogies & Real-world Examples"
        case .examples: return "Practical Examples"
        case .technical: return "Technical Definitions"
        case .simple: return "Simple Language"
        case .visual: return "Visual Descriptions"
        }
    }
    
    var systemPrompt: String {
        switch self {
        case .analogies:
            return "Explain using analogies and real-world examples. Start with something familiar from everyday life, then show how it applies."
        case .examples:
            return "Give 2-3 practical examples showing how this works in real situations."
        case .technical:
            return "Provide a precise technical definition with key details and related concepts."
        case .simple:
            return "Explain in plain language, like you're talking to a smart 12-year-old. Avoid jargon."
        case .visual:
            return "Paint a mental picture - describe how it would look or feel using spatial and visual metaphors."
        }
    }
}