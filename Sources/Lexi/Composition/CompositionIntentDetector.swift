import Foundation

/// Decides whether a spoken/typed instruction is a "compose / command" request
/// (write, transform, or edit text in the focused app) versus a genuine question
/// that should be answered in the Lexi panel.
///
/// Design notes:
/// - A strong *leading* trigger ("write …", "make this more concise?") wins even
///   when the phrase ends in a question mark, because polite commands are often
///   phrased as questions ("can you shorten this?").
/// - The question guard only fires when no strong compose trigger is present, so
///   real questions ("what does this mean?", "explain this") are never treated as
///   compose commands.
enum CompositionIntentDetector {
    static func isCompositionInstruction(_ text: String) -> Bool {
        let normalized = normalizedInstruction(text)
        guard !normalized.isEmpty else { return false }
        let stripped = strippedPreamble(from: normalized)
        let tokens = tokenize(stripped)

        // 1. A strong leading trigger ("write …", "make this concise?", "shorten it")
        //    is unambiguous and beats the question-mark heuristic below.
        if hasLeadingComposeTrigger(stripped: stripped, tokens: tokens) {
            return true
        }

        // 2. Otherwise, a question is a question — answer it, don't compose.
        if isAnswerQuestion(stripped) {
            return false
        }

        // 3. Transformation signals describe an edit even without a leading verb
        //    ("a bit more professional", "no em dashes").
        if containsTransformationSignal(normalized) {
            return true
        }

        // 4. A trigger verb anywhere in the sentence, paired with a writing noun or
        //    transformation target, is a compose command ("for that, draft an email").
        if containsTriggerVerb(tokens) && (containsNounSignal(normalized) || containsTransformationSignal(normalized)) {
            return true
        }

        // 5. Fall back to writing-artifact nouns ("a thank-you note", "an outline").
        return containsNounSignal(normalized)
    }

    static func isWholeDeletionInstruction(_ text: String) -> Bool {
        let normalized = normalizedInstruction(text)
        guard !normalized.isEmpty else { return false }
        let stripped = strippedPreamble(from: normalized)
        let wholeDeletePrefixes = [
            "delete this", "delete it", "delete that", "delete selected", "delete the selected", "delete selection",
            "remove this", "remove it", "remove that", "remove selected", "remove the selected", "remove selection",
            "cut this", "cut it", "cut that", "cut selected", "cut the selected",
            "erase this", "erase it", "erase that",
            "clear this", "clear it", "clear that", "clear selection",
            "wipe this", "wipe it", "wipe that",
            "scrap this", "scrap it", "scrap that",
            "get rid of this", "get rid of it", "get rid of that"
        ]
        guard wholeDeletePrefixes.contains(where: { stripped.hasPrefix($0) }) else { return false }
        // Bare "delete this" with no further qualifier is a whole-selection delete.
        // "delete the commas" / "remove the em dashes" is a transform, not a wipe.
        // Match whole words only: substring matching would mis-fire on "delete this
        // password" ("word"), "erase this headline" ("line"), "cut this command" ("comma").
        let transformTargets: Set<String> = ["dash", "dashes", "hyphen", "hyphens", "comma", "commas",
                                             "space", "spaces", "line", "lines", "word", "words",
                                             "sentence", "sentences", "typo", "typos"]
        let tokens = Set(tokenize(stripped))
        return transformTargets.isDisjoint(with: tokens)
    }

    // MARK: - Trigger vocabulary

    /// Imperative verbs that, at the start of a command, mean "write / transform text".
    private static let leadingVerbs: Set<String> = [
        // write / produce new text
        "write", "type", "jot", "note", "scribble", "pen", "author", "draft", "compose",
        "generate", "produce", "create", "make", "enter", "insert", "input", "key",
        "add", "fill", "put", "spell", "draw",
        // respond
        "respond", "reply",
        // rewrite / transform
        "rewrite", "reword", "rephrase", "paraphrase", "revise", "edit", "redo",
        "reformat", "format", "restructure", "rework",
        // shorten
        "summarize", "summarise", "shorten", "condense", "tighten", "trim",
        "abbreviate", "compress", "truncate",
        // expand
        "expand", "elaborate", "lengthen", "extend", "continue", "finish", "complete",
        // tone / quality
        "professionalize", "professionalise", "formalize", "formalise",
        "polish", "refine", "improve", "enhance", "humanize", "humanise",
        "simplify", "clarify", "punctuate", "capitalize", "capitalise",
        "bulletize", "bullet", "list", "outline",
        // fix
        "fix", "correct", "proofread", "tidy", "clean", "spruce",
        // translate / convert
        "translate", "convert", "turn", "transform", "change", "swap", "replace", "update",
        // delete (single-token; whole-deletion handled separately)
        "delete", "remove", "cut", "erase", "omit", "strip"
    ]

    /// Multi-word leading phrases (checked against the first two tokens).
    private static let leadingPhrases: Set<String> = [
        "write down", "write up", "write out",
        "type out", "type up", "type in",
        "note down", "jot down", "put down", "spell out", "draw up",
        "fill in", "fill out", "key in",
        "clean up", "tidy up", "sum up", "spruce up", "dumb down",
        "flesh out", "build out", "lay out", "bullet point",
        "make this", "make it", "make that"
    ]

    /// Trigger verbs that may appear anywhere (not only leading). Kept identical to
    /// the leading set so that words like "explain"/"answer" never count as a trigger.
    private static let anywhereTriggerVerbs: Set<String> = leadingVerbs

    private static func hasLeadingComposeTrigger(stripped: String, tokens: [String]) -> Bool {
        guard let first = tokens.first else { return false }
        if leadingVerbs.contains(first) {
            return true
        }
        if tokens.count >= 2 {
            let pair = "\(tokens[0]) \(tokens[1])"
            if leadingPhrases.contains(pair) {
                return true
            }
        }
        // "make/turn this/it … into/more …" handled by leadingPhrases + verb; also
        // catch "turn this into" style.
        if (first == "turn" || first == "make") && tokens.count >= 2 {
            return true
        }
        return false
    }

    private static func containsTriggerVerb(_ tokens: [String]) -> Bool {
        tokens.contains { anywhereTriggerVerbs.contains($0) }
    }

    private static func containsTransformationSignal(_ normalized: String) -> Bool {
        let transformationSignals = [
            "more concise", "less wordy", "more professional", "more casual",
            "more formal", "more friendly", "more polite", "more direct",
            "more readable", "better written", "easier to read",
            "grammatically correct", "fix the grammar", "fix grammar",
            "fix typos", "fix the typos", "fewer words", "in plain english",
            "bullet points", "in bullets", "as a list",
            "fewer em dashes", "fewer m-dashes", "fewer m dashes", "less em dashes",
            "no em dashes", "no m-dashes", "remove em dashes", "remove m-dashes",
            "more concisely", "less formal", "in my voice", "in a friendlier tone",
            "in a professional tone"
        ]
        return transformationSignals.contains { normalized.contains($0) }
    }

    private static func containsNounSignal(_ normalized: String) -> Bool {
        let nounSignals = [
            "financial model", "essay", "paragraph", "table", "reply", "response",
            "draft", "plan", "outline", "message", "email", "note", "list", "template",
            "caption", "post", "proposal", "memo", "summary", "letter", "headline",
            "subject line", "bullet points", "agenda", "script", "tweet", "abstract",
            "intro", "introduction", "conclusion", "paragraphs", "sentence", "blurb"
        ]
        return nounSignals.contains { normalized.contains($0) }
    }

    // MARK: - Question guard

    private static func isAnswerQuestion(_ stripped: String) -> Bool {
        let answerPrefixes = [
            "what ", "what's ", "whats ", "why ", "how ", "when ", "where ", "who ",
            "which ", "whose ", "whom ",
            "should i ", "what should i ", "can i ", "do i ", "did i ", "does this ",
            "is this ", "is that ", "are these ", "are those ", "was this ",
            "define ", "definition of", "meaning of", "what does", "what is",
            "answer this", "answer the", "explain this", "explain the", "explain ",
            "tell me"
            // Note: "summarize"/"describe" are leading compose verbs (step 1 wins),
            // so "summarize what …" intentionally composes a summary rather than
            // being answered — no unreachable prefixes listed here.
        ]
        if answerPrefixes.contains(where: { stripped.hasPrefix($0) }) {
            return true
        }
        // A trailing "?" marks a question only when there's no leading compose verb
        // (those were already accepted above before this guard runs).
        return stripped.hasSuffix("?")
    }

    // MARK: - Normalization

    private static func normalizedInstruction(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func strippedPreamble(from normalized: String) -> String {
        let preambles = [
            "hey lexi ", "lexi ", "ok ", "okay ", "so ", "now ", "alright ",
            "can you ", "could you ", "would you ", "will you ", "please ",
            "help me ", "i need you to ", "i need to ", "i want you to ", "i want to ",
            "i'd like you to ", "i would like you to ", "let's ", "lets ", "go ahead and ",
            "just ", "for me "
        ]
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
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}
