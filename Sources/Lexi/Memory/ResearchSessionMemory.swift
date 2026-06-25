import Foundation

@MainActor
final class ResearchSessionMemory {
    struct Entry {
        let prompt: String
        let answer: String
        let source: String
        let createdAt: Date
    }

    private var entries: [Entry] = []
    private let maxEntries = 8

    var contextSummary: String {
        entries.suffix(5).map { entry in
            let prompt = entry.prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)
            let answer = entry.answer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(260)
            return "- [\(entry.source)] \(prompt) → \(answer)"
        }.joined(separator: "\n")
    }

    var keyterms: [String] {
        var terms: [String] = []
        for entry in entries.suffix(5) {
            terms.append(contentsOf: Self.extractKeyterms(from: entry.prompt))
            terms.append(contentsOf: Self.extractKeyterms(from: entry.answer))
        }
        return Array(Self.unique(terms).prefix(24))
    }

    func record(prompt: String, answer: String, source: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !trimmedAnswer.isEmpty else { return }
        entries.append(Entry(prompt: trimmedPrompt, answer: trimmedAnswer, source: source, createdAt: Date()))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func keyterms(extraText: [String]) -> [String] {
        var terms = keyterms
        for text in extraText {
            terms.append(contentsOf: Self.extractKeyterms(from: text))
        }
        return Array(Self.unique(terms).prefix(32))
    }

    static func extractKeyterms(from text: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: ".#+-/"))
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                guard token.count >= 3, token.count <= 48 else { return false }
                if token.allSatisfy({ $0.isNumber }) { return false }
                if commonWords.contains(token.lowercased()) { return false }
                return token.contains { $0.isUppercase } || token.contains(".") || token.contains("#") || token.contains("+") || token.count >= 7
            }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(trimmed)
        }
        return output
    }

    private static let commonWords: Set<String> = [
        "about", "after", "again", "answer", "because", "before", "being", "between", "could", "does", "doing", "from", "have", "into", "like", "more", "most", "other", "should", "that", "their", "there", "these", "thing", "this", "through", "under", "using", "what", "when", "where", "which", "while", "with", "without", "would", "your"
    ]
}
