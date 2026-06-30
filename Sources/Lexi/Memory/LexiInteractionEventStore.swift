import Foundation

@MainActor
final class LexiInteractionEventStore {
    static let shared = LexiInteractionEventStore()
    private static let maxStoredLines = 500

    struct Event: Codable {
        let schemaVersion: Int
        let id: UUID
        let createdAt: Date
        let promptPreview: String
        let answerPreview: String
        let prompt: String?
        let answer: String?
        let source: String
        let appName: String
        let windowTitle: String
        let route: String
        let latencyTier: String
        let model: String
        let researchUsed: Bool
        let researchProvider: String
        let totalMs: Int
        let outputCharacters: Int
    }

    private let encoder: JSONEncoder
    private let eventsURL: URL

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryURL = baseURL.appendingPathComponent("Lexi", isDirectory: true)
        eventsURL = directoryURL.appendingPathComponent("interaction-events.jsonl")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func record(prompt: String, answer: String, source: String, appName: String, windowTitle: String, diagnostics: LexiDiagnosticsSnapshot = LexiDiagnostics.snapshot) {
        let event = Event(
            schemaVersion: 2,
            id: UUID(),
            createdAt: Date(),
            promptPreview: Self.preview(prompt, limit: 240),
            answerPreview: Self.preview(answer, limit: 520),
            prompt: prompt,
            answer: answer,
            source: source,
            appName: Self.preview(appName, limit: 120),
            windowTitle: Self.preview(windowTitle, limit: 180),
            route: diagnostics.lastRoute,
            latencyTier: diagnostics.lastLatencyTier,
            model: diagnostics.lastModel,
            researchUsed: diagnostics.lastResearchUsed,
            researchProvider: diagnostics.lastResearchProvider,
            totalMs: diagnostics.lastTotalMs,
            outputCharacters: diagnostics.lastOutputCharacters
        )

        guard let data = try? encoder.encode(event) else { return }
        appendLine(data)
    }

    func recentEvents(limit: Int = 50) -> [Event] {
        guard limit > 0 else { return [] }
        return decodedEvents()
            .reversed()
            .filter { !$0.displayPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(limit)
            .map { $0 }
    }

    func clearHistory() {
        try? FileManager.default.removeItem(at: eventsURL)
    }

    func event(id: UUID) -> Event? {
        decodedEvents().reversed().first { $0.id == id }
    }

    func relevantContextSummary(for query: String, limit: Int = 4) -> String {
        let queryTerms = Self.keyterms(from: query)
        let events = decodedEvents(limit: 240)
        guard !queryTerms.isEmpty, !events.isEmpty else { return "" }
        let ranked = events.compactMap { event -> (Int, Event)? in
            let haystack = "\(event.promptPreview) \(event.answerPreview) \(event.appName) \(event.windowTitle)".lowercased()
            let score = queryTerms.reduce(0) { partial, term in
                partial + (haystack.contains(term) ? 1 : 0)
            }
            return score > 0 ? (score, event) : nil
        }
        .sorted { lhs, rhs in
            if lhs.0 == rhs.0 { return lhs.1.createdAt > rhs.1.createdAt }
            return lhs.0 > rhs.0
        }
        .prefix(limit)

        return ranked.map { _, event in
            "- [\(event.source), route=\(event.route.isEmpty ? "unknown" : event.route)] \(event.promptPreview) → \(event.answerPreview)"
        }.joined(separator: "\n")
    }

    private func appendLine(_ data: Data) {
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: eventsURL) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data([10]))
        try? handle.close()
        trimToRecent(maxLines: Self.maxStoredLines)
    }

    private func trimToRecent(maxLines: Int) {
        guard maxLines > 0,
              let text = try? String(contentsOf: eventsURL, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        guard lines.count > maxLines else { return }
        let trimmed = lines.suffix(maxLines).joined(separator: "\n") + "\n"
        try? trimmed.write(to: eventsURL, atomically: true, encoding: .utf8)
    }

    private func decodedEvents(limit: Int? = nil) -> [Event] {
        guard let data = try? Data(contentsOf: eventsURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = text
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(Event.self, from: Data(String(line).utf8))
            }
        if let limit {
            return Array(events.suffix(limit))
        }
        return events
    }

    private static func preview(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(limit))
    }

    private static func keyterms(from text: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: ".#+-/"))
        var seen = Set<String>()
        return text
            .lowercased()
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                guard token.count >= 4, token.count <= 48, !commonWords.contains(token) else { return false }
                guard !seen.contains(token) else { return false }
                seen.insert(token)
                return true
            }
    }

    private static let commonWords: Set<String> = [
        "about", "after", "again", "answer", "because", "before", "being", "between", "could", "does", "doing", "from", "have", "into", "like", "more", "most", "other", "should", "that", "their", "there", "these", "thing", "this", "through", "under", "using", "what", "when", "where", "which", "while", "with", "without", "would", "your"
    ]
}

extension LexiInteractionEventStore.Event {
    var displayPrompt: String {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? promptPreview : trimmed
    }

    var displayAnswer: String {
        let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? answerPreview : trimmed
    }

    var relativeTimestamp: String {
        Self.relativeTimestamp(for: createdAt)
    }

    static func relativeTimestamp(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 45 { return "just now" }
        if interval < 90 { return "1m ago" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(interval / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(interval / 86400)
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
