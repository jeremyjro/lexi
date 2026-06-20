# Lexi

A macOS application that provides instant, context-aware explanations for unfamiliar words and concepts as you read. Simply hold the function key, highlight any text, and get a personalized explanation without breaking your learning flow.

## Vision

Lexi solves the problem of context-switching when you encounter unfamiliar terms while reading. Instead of opening a new tab or switching to an AI chatbot, the assistant follows your cursor and provides instant, tailored explanations right where you're reading.

## Features

- **Context-Aware Explanations**: Analyzes surrounding text to provide relevant explanations
- **Personalized Learning Styles**: Choose how you learn best (analogies, examples, technical, simple, visual)
- **Non-Intrusive UI**: Animated bubble that appears near your cursor without blocking content
- **Keyboard Trigger**: Hold function key + highlight text to trigger
- **Fast Responses**: Optimized for quick explanations to maintain flow state

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Platform**: macOS 14+
- **AI Service**: Anthropic Claude API
- **System Integration**: macOS Accessibility API

## Architecture

```
CursorAssistant/
├── Sources/CursorAssistant/
│   ├── main.swift              # App entry point and coordination
│   ├── Models/                 # Data models
│   │   ├── LearningStyle.swift # Learning preference configurations
│   │   └── BubbleState.swift   # UI state management
│   ├── Views/                  # SwiftUI views
│   │   └── BubbleView.swift    # Animated bubble UI
│   ├── Services/               # Core services
│   │   ├── ClaudeAIService.swift      # AI API integration
│   │   ├── AccessibilityManager.swift # Text selection detection
│   │   └── BubbleController.swift     # Window management
│   └── Utilities/              # Helper functions
└── Resources/                  # Assets and configurations
```

## Setup

### Prerequisites

- macOS 14 or later
- Xcode 15 or later
- Anthropic API key

### Installation

1. Clone the repository:
```bash
cd /Volumes/T7/Projects/Jeremy/CursorAssistant
```

2. Set your Anthropic API key:
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

3. Build the project:
```bash
swift build
```

4. Run the application:
```bash
swift run CursorAssistant
```

### Permissions

On first launch, you'll need to grant Accessibility permissions:
1. Open System Preferences → Privacy & Security → Accessibility
2. Add CursorAssistant to the list of allowed applications
3. Restart the application

## Usage

1. Launch Lexi
2. Hold the **Option+Command** keys on your keyboard
3. Highlight any word or phrase in any application
4. Release the Option+Command keys
5. A bubble will appear with a personalized explanation

### Customizing Learning Style

Edit the `LearningStyle` in `main.swift` to match your preference:
- `.analogies` - Real-world analogies and examples
- `.examples` - Practical examples
- `.technical` - Technical definitions
- `.simple` - Simple, jargon-free language
- `.visual` - Visual descriptions

## Development

### Building for Distribution

```bash
swift build -c release
```

### Running Tests

```bash
swift test
```

## Future Enhancements

- [ ] Add caching for common terms
- [ ] Implement offline mode with local LLM
- [ ] Add pronunciation guide
- [ ] Support for multiple languages
- [ ] Statistics dashboard for learned concepts
- [ ] Export learning history

## License

Personal project for Jeremy R.

## Acknowledgments

Built with Claude API for intelligent explanations and macOS Accessibility API for system-wide text detection.