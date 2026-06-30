import Foundation

enum CompositionIntentDetector {
    static func isCompositionInstruction(_ text: String) -> Bool {
        let normalized = normalizedInstruction(text)
        guard !normalized.isEmpty else { return false }
        let stripped = strippedPreamble(from: normalized)
        if isAnswerQuestion(stripped) {
            return false
        }

        let triggerPhrases = [
            "write", "draft", "generate", "compose", "create", "make", "model", "build",
            "outline", "turn", "convert", "rewrite", "reword", "format", "fill in",
            "insert", "type", "respond", "reply", "summarize", "shorten", "tighten",
            "polish", "improve", "edit", "clean up", "fix grammar", "proofread",
            "simplify", "expand", "elaborate", "professionalize", "humanize",
            "delete", "remove", "cut", "erase", "omit"
        ]
        if triggerPhrases.contains(where: { stripped.hasPrefix($0) || normalized.contains(" \($0) ") }) {
            return true
        }

        let transformationSignals = [
            "more concise", "less wordy", "shorter", "clearer", "more professional",
            "more casual", "better written", "grammatically correct", "fix typos",
            "fewer em dashes", "fewer m-dashes", "fewer m dashes", "less em dashes",
            "no em dashes", "no m-dashes", "remove em dashes", "remove m-dashes"
        ]
        if transformationSignals.contains(where: { normalized.contains($0) }) {
            return true
        }

        let nounSignals = ["financial model", "essay", "paragraph", "table", "reply", "response", "draft", "plan", "outline", "message", "email", "note", "list", "template", "caption", "post", "proposal", "memo"]
        return nounSignals.contains { normalized.contains($0) }
    }

    static func isWholeDeletionInstruction(_ text: String) -> Bool {
        let normalized = normalizedInstruction(text)
        guard !normalized.isEmpty else { return false }
        let stripped = strippedPreamble(from: normalized)
        let wholeDeletePrefixes = [
            "delete this", "delete it", "delete selected", "delete the selected", "delete selection",
            "remove this", "remove it", "remove selected", "remove the selected", "remove selection",
            "cut this", "cut it", "cut selected", "cut the selected", "erase this", "erase it"
        ]
        guard wholeDeletePrefixes.contains(where: { stripped.hasPrefix($0) }) else { return false }
        if stripped.hasPrefix("delete") || stripped.hasPrefix("cut") || stripped.hasPrefix("erase") {
            return true
        }
        let transformTargets = ["dash", "dashes", "hyphen", "hyphens", "comma", "commas"]
        return !transformTargets.contains { stripped.contains($0) }
    }

    private static func isAnswerQuestion(_ stripped: String) -> Bool {
        let answerPrefixes = [
            "what ", "why ", "how ", "when ", "where ", "who ", "which ",
            "should i ", "what should i ", "can i ", "do i ", "does this ",
            "is this ", "are these ", "answer this", "explain this", "tell me"
        ]
        if answerPrefixes.contains(where: { stripped.hasPrefix($0) }) {
            return true
        }
        return stripped.hasSuffix("?") && !stripped.hasPrefix("write") && !stripped.hasPrefix("draft") && !stripped.hasPrefix("reply") && !stripped.hasPrefix("respond")
    }

    private static func normalizedInstruction(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func strippedPreamble(from normalized: String) -> String {
        let preambles = ["can you ", "could you ", "would you ", "please ", "help me ", "i need you to ", "i want you to ", "i'd like you to ", "just "]
        var stripped = normalized
        var didStrip = true
        while didStrip {
            didStrip = false
            for preamble in preambles where stripped.hasPrefix(preamble) {
                stripped = String(stripped.dropFirst(preamble.count))
                didStrip = true
                break
            }
        }
        return stripped
    }
}
