# Context-Aware Query Inference Backend

## Overview

This backend system provides intelligent query inference that predicts what a user wants to know based on highlighted text, surrounding context, and user persona. The system eliminates the need for users to manually type questions by automatically inferring their intent.

## Key Features

- **Persona-Aware Inference**: Adapts predictions based on user's background (Go-to-Market, Technical, Executive, Student, General)
- **Context Analysis**: Understands app context (Twitter, iMessage, VS Code, etc.) and content type
- **Term Classification**: Identifies term types (technical jargon, slang, abbreviations, etc.)
- **Edge Case Handling**: Manages ambiguous text, insufficient context, and privacy concerns
- **Privacy-First**: Built-in privacy checks to prevent processing sensitive information

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Inference Orchestrator                     │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  1. Enhanced Context Analyzer                            │ │
│  │     - App Detection & Classification                      │ │
│  │     - Content Type Analysis                               │ │
│  └──────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  2. Term Analyzer                                         │ │
│  │     - Rule-based Classification                           │ │
│  │     - AI-powered Analysis                                 │ │
│  │     - Domain Detection                                    │ │
│  └──────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  3. Persona-Aware Query Generator                         │ │
│  │     - Persona-specific Prompts                            │ │
│  │     - Context-aware Question Generation                   │ │
│  │     - Explanation Approach Selection                       │ │
│  └──────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  4. Edge Case Handler                                     │ │
│  │     - Ambiguity Detection                                 │ │
│  │     - Privacy Checks                                      │ │
│  │     - Fallback Strategies                                 │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Usage Examples

### Basic Usage

```swift
import Foundation

// Initialize the orchestrator with your API key
let orchestrator = InferenceOrchestrator(apiKey: "your-anthropic-api-key")

// Perform inference
let response = await orchestrator.inferUserQuery(
    highlightedText: "agent cloud",
    surroundingContext: "Cognito's new agent cloud thesis represents a paradigm shift in how we think about AI deployment and infrastructure.",
    appName: "Twitter",
    bundleIdentifier: "com.twitter.twitter",
    windowTitle: "Twitter / X"
)

print("Inferred Question: \(response.inferredQuery.inferredQuestion)")
print("Confidence: \(response.inferredQuery.confidence)")
print("Term Type: \(response.termAnalysis.termType)")
```

### Go-to-Market Persona Example

```swift
// Set up user profile
let profileManager = UserProfileManager()
profileManager.updatePersona(.goToMarket)

// Technical term in business context
let response = await orchestrator.inferUserQuery(
    highlightedText: "serverless",
    surroundingContext: "Our new serverless architecture will reduce costs and improve scalability for enterprise clients.",
    appName: "Twitter",
    bundleIdentifier: "com.twitter.twitter",
    windowTitle: nil
)

// Expected output:
// "What does 'serverless' mean for our business and why is it important for enterprise clients?"
```

### Messaging/Slang Example

```swift
// Slang in messaging context
let response = await orchestrator.inferUserQuery(
    highlightedText: "ghost",
    surroundingContext: "I can't believe he ghosted me after our meeting yesterday",
    appName: "Messages",
    bundleIdentifier: "com.apple.iChat",
    windowTitle: "John Doe"
)

// Expected output:
// "What does 'ghost' mean in this conversation context?"
// Approach: urbanDictionary
```

### Technical Persona Example

```swift
// Set technical persona
profileManager.updatePersona(.technical)

// Technical term in code context
let response = await orchestrator.inferUserQuery(
    highlightedText: "GraphQL",
    surroundingContext: "We're migrating our REST API to GraphQL for more flexible data fetching.",
    appName: "VS Code",
    bundleIdentifier: "com.microsoft.VSCode",
    windowTitle: "api_migration.ts"
)

// Expected output:
// "How is GraphQL implemented and what are the technical tradeoffs compared to REST?"
```

## Persona System

### Available Personas

1. **Go-to-Market**: Business/sales focus, needs technical terms explained in business context
2. **Technical**: Engineering background, understands technical but needs business context
3. **Executive**: Strategic focus, needs high-level implications and ROI
4. **Student**: Learning focus, needs foundational explanations with analogies
5. **General**: Balanced approach, adapts to context

### Persona Configuration

```swift
// Get recommended persona based on description
let recommendedPersona = PersonaConfiguration.getRecommendedPersona(
    for: "I work in marketing and sales"
)
// Returns: .goToMarket

// Set persona explicitly
profileManager.updatePersona(.goToMarket)

// Customize explanation style
profileManager.updateExplanationStyle(.analogy)

// Add user interests
profileManager.addInterest("SaaS metrics")
profileManager.addInterest("B2B sales")

// Add expertise areas
profileManager.addExpertiseArea("Customer success")
```

## Context Analysis

### App Categories

The system automatically detects app context:

- **Social Media**: Twitter, Facebook, LinkedIn, Reddit
- **Messaging**: Messages, WhatsApp, Discord, Slack
- **Code Editor**: VS Code, Xcode, IntelliJ, Sublime
- **Browser**: Chrome, Safari, Firefox, Edge
- **Document**: Word, Pages, PDF readers
- **Email**: Mail, Outlook, Gmail
- **Notes**: Notes, Notion, Evernote
- **Terminal**: Terminal, iTerm2

### Content Types

Automatically classified content types:
- Technical, Slang, Abbreviation, Formal, Casual
- Business, Code, Documentation, News, Opinion
- Personal, Mixed

## Term Analysis

### Term Types

- **technical_jargon**: Specialized technical terminology
- **industry_slang**: Casual industry-specific language
- **abbreviation**: Shortened form of a word
- **acronym**: Abbreviation pronounced as a word
- **foreign_word**: Word from another language
- **domain_specific**: Specialized vocabulary for a field
- **proper_noun**: Name of specific person, place, or organization
- **general_vocabulary**: Common words
- **emoji**: Emoji characters
- **unknown**: Cannot classify

### Explanation Approaches

- **first_principles**: Break down to fundamental concepts
- **analogy**: Use comparisons to explain
- **example**: Provide concrete examples
- **definition**: Direct definition
- **context**: Explain based on usage context
- **urban_dictionary**: Casual/slang explanation
- **technical**: Technical explanation
- **business**: Business-focused explanation
- **simplified**: Simple, non-technical explanation

## Edge Case Handling

### Detected Edge Cases

1. **Ambiguous Text**: Terms with multiple possible meanings
2. **Insufficient Context**: Not enough surrounding information
3. **Multiple Interpretations**: Term could be understood different ways
4. **Persona Mismatch**: Term doesn't match user's expertise
5. **Unknown Term**: Cannot classify the term
6. **Mixed Content**: Content spans multiple categories
7. **No Clear Intent**: Highlighted text doesn't need explanation
8. **Privacy Sensitive**: Contains sensitive information

### Fallback Strategies

- **generic_explanation**: Provide a general explanation
- **ask_for_clarification**: Request user input
- **provide_multiple_options**: Offer alternative questions
- **use_simple_definition**: Use simplified definition
- **skip_inference**: Don't process (privacy concerns)
- **request_more_context**: Ask for more surrounding text

## Configuration

### Inference Configuration

```swift
let config = InferenceConfiguration.shared

// Adjust confidence threshold
config.updateConfiguration(confidenceThreshold: 0.6)

// Enable/disable edge case detection
config.updateConfiguration(enableEdgeCaseDetection: true)

// Privacy settings
config.updateConfiguration(enablePrivacyChecks: true)

// Context settings
config.updateConfiguration(maxContextLength: 500)

// Cache settings
config.updateConfiguration(cacheEnabled: true)
config.updateConfiguration(cacheExpirationHours: 24)
```

## Advanced Usage

### Batch Processing

```swift
let terms = [
    (text: "SaaS", context: "Our SaaS platform serves enterprise clients", appName: "Twitter"),
    (text: "churn", context: "Reducing churn is critical for growth", appName: "Messages"),
    (text: "API", context: "The API provides data access", appName: "VS Code")
]

let responses = await orchestrator.batchInfer(terms: terms)

for response in responses {
    print("\(response.inferredQuery.originalText): \(response.inferredQuery.inferredQuestion)")
}
```

### Quick Inference

```swift
// Simplified inference for real-time performance
let question = await orchestrator.quickInfer(
    highlightedText: "microservices",
    surroundingContext: "We're moving to microservices architecture",
    appName: "Slack"
)
```

### Privacy Check

```swift
// Check if content should be processed
let shouldProcess = orchestrator.shouldProcessInference(
    highlightedText: "API key",
    surroundingContext: "My API key is sk-1234567890"
)
// Returns: false (privacy sensitive)
```

## Integration with Existing System

To integrate with the existing Lexi system:

```swift
// In your existing ContextInferenceService
class ContextInferenceService {
    private let orchestrator: InferenceOrchestrator
    
    init(apiKey: String) {
        self.orchestrator = InferenceOrchestrator(apiKey: apiKey)
    }
    
    func collectContext() -> AppContext {
        // Your existing context collection logic
        // ...
    }
    
    func inferUserIntent(context: AppContext) async -> String {
        let response = await orchestrator.inferUserQuery(
            highlightedText: context.selectedText ?? "",
            surroundingContext: context.surroundingText ?? "",
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            screenshotData: context.screenshotData
        )
        
        return response.inferredQuery.inferredQuestion
    }
}
```

## Performance Considerations

- **Latency**: Typical inference takes 1-3 seconds
- **Caching**: Enable caching for repeated terms
- **Confidence Threshold**: Adjust based on your use case
- **Context Window**: Limit context length for faster processing

## Privacy & Security

- **No Data Storage**: No user data is stored permanently
- **Privacy Checks**: Automatic detection of sensitive content
- **Local Processing**: Context analysis happens locally
- **API Security**: Uses secure API connections

## Troubleshooting

### Low Confidence Scores

- Increase context window size
- Check if term is in user's expertise areas
- Verify app context detection is working

### Incorrect Persona Detection

- Manually set persona using `updatePersona()`
- Add user interests and expertise areas
- Adjust explanation style preferences

### Privacy False Positives

- Review privacy check patterns in EdgeCaseHandler
- Adjust sensitivity in configuration
- Add exceptions for specific use cases

## Future Enhancements

- Machine learning-based persona detection
- User behavior analysis for persona refinement
- Multi-language support
- Voice input for query refinement
- Integration with knowledge bases
- Collaborative filtering for explanation quality

## API Reference

### InferenceOrchestrator

Main coordinator for the inference system.

```swift
init(apiKey: String)
func inferUserQuery(highlightedText:surroundingContext:appName:bundleIdentifier:windowTitle:screenshotData:) async -> InferenceResponse
func quickInfer(highlightedText:surroundingContext:appName:) async -> String
func shouldProcessInference(highlightedText:surroundingContext:) -> Bool
func batchInfer(terms:) async -> [InferenceResponse]
```

### UserProfileManager

Manages user persona and preferences.

```swift
func getCurrentProfile() -> UserProfile
func saveProfile(_ profile: UserProfile)
func updatePersona(_ persona: UserPersona)
func updateExplanationStyle(_ style: ExplanationStyle)
func addInterest(_ interest: String)
func addExpertiseArea(_ area: String)
```

### PersonaConfiguration

Provides persona profiles and recommendations.

```swift
static let personas: [UserPersona: PersonaProfile]
static func getPersonaProfile(for persona: UserPersona) -> PersonaProfile?
static func getRecommendedPersona(for userDescription: String) -> UserPersona
```

## Support

For issues or questions, refer to the main project documentation or contact the development team.