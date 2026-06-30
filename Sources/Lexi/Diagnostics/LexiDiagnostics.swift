import Foundation

struct LexiDiagnosticsSnapshot {
    let lastEvent: String
    let lastExplainRequestBytes: Int
    let lastHTTPStatus: Int
    let lastBuddyImageBytes: Int
    let lastBuddyImageDescription: String
    let lastBuddyOCRCharacters: Int
    let lastModel: String
    let lastRoute: String
    let lastLatencyTier: String
    let lastResearchUsed: Bool
    let lastResearchProvider: String
    let lastTotalMs: Int
    let lastOutputCharacters: Int
    let updatedAt: Date?

    var summary: String {
        let formatter = ISO8601DateFormatter()
        return """
        Last event: \(lastEvent)
        Last /explain bytes: \(lastExplainRequestBytes == 0 ? "Unknown" : "\(lastExplainRequestBytes)")
        Last HTTP status: \(lastHTTPStatus == 0 ? "Unknown" : "\(lastHTTPStatus)")
        Last Buddy image: \(lastBuddyImageDescription.isEmpty ? "Unknown" : lastBuddyImageDescription)
        Last Buddy OCR chars: \(lastBuddyOCRCharacters == 0 ? "None/unknown" : "\(lastBuddyOCRCharacters)")
        Last model: \(lastModel.isEmpty ? "Unknown" : lastModel)
        Last route: \(lastRoute.isEmpty ? "Unknown" : lastRoute)
        Last latency tier: \(lastLatencyTier.isEmpty ? "Unknown" : lastLatencyTier)
        Last research: \(lastResearchUsed ? (lastResearchProvider.isEmpty ? "Yes" : lastResearchProvider) : "No")
        Last total latency: \(lastTotalMs == 0 ? "Unknown" : "\(lastTotalMs)ms")
        Last output chars: \(lastOutputCharacters == 0 ? "Unknown" : "\(lastOutputCharacters)")
        Updated: \(updatedAt.map { formatter.string(from: $0) } ?? "Never")
        """
    }
}

enum LexiDiagnostics {
    private static let lastEventKey = "LexiDiagnosticsLastEvent"
    private static let lastExplainRequestBytesKey = "LexiDiagnosticsLastExplainRequestBytes"
    private static let lastHTTPStatusKey = "LexiDiagnosticsLastHTTPStatus"
    private static let lastBuddyImageBytesKey = "LexiDiagnosticsLastBuddyImageBytes"
    private static let lastBuddyImageDescriptionKey = "LexiDiagnosticsLastBuddyImageDescription"
    private static let lastBuddyOCRCharactersKey = "LexiDiagnosticsLastBuddyOCRCharacters"
    private static let lastModelKey = "LexiDiagnosticsLastModel"
    private static let lastRouteKey = "LexiDiagnosticsLastRoute"
    private static let lastLatencyTierKey = "LexiDiagnosticsLastLatencyTier"
    private static let lastResearchUsedKey = "LexiDiagnosticsLastResearchUsed"
    private static let lastResearchProviderKey = "LexiDiagnosticsLastResearchProvider"
    private static let lastTotalMsKey = "LexiDiagnosticsLastTotalMs"
    private static let lastOutputCharactersKey = "LexiDiagnosticsLastOutputCharacters"
    private static let updatedAtKey = "LexiDiagnosticsUpdatedAt"

    static var snapshot: LexiDiagnosticsSnapshot {
        let updatedTime = UserDefaults.standard.double(forKey: updatedAtKey)
        return LexiDiagnosticsSnapshot(
            lastEvent: UserDefaults.standard.string(forKey: lastEventKey) ?? "None",
            lastExplainRequestBytes: UserDefaults.standard.integer(forKey: lastExplainRequestBytesKey),
            lastHTTPStatus: UserDefaults.standard.integer(forKey: lastHTTPStatusKey),
            lastBuddyImageBytes: UserDefaults.standard.integer(forKey: lastBuddyImageBytesKey),
            lastBuddyImageDescription: UserDefaults.standard.string(forKey: lastBuddyImageDescriptionKey) ?? "",
            lastBuddyOCRCharacters: UserDefaults.standard.integer(forKey: lastBuddyOCRCharactersKey),
            lastModel: UserDefaults.standard.string(forKey: lastModelKey) ?? "",
            lastRoute: UserDefaults.standard.string(forKey: lastRouteKey) ?? "",
            lastLatencyTier: UserDefaults.standard.string(forKey: lastLatencyTierKey) ?? "",
            lastResearchUsed: UserDefaults.standard.bool(forKey: lastResearchUsedKey),
            lastResearchProvider: UserDefaults.standard.string(forKey: lastResearchProviderKey) ?? "",
            lastTotalMs: UserDefaults.standard.integer(forKey: lastTotalMsKey),
            lastOutputCharacters: UserDefaults.standard.integer(forKey: lastOutputCharactersKey),
            updatedAt: updatedTime > 0 ? Date(timeIntervalSince1970: updatedTime) : nil
        )
    }

    static func recordEvent(_ event: String) {
        UserDefaults.standard.set(event, forKey: lastEventKey)
        touch()
    }

    static func recordExplainRequest(bytes: Int) {
        UserDefaults.standard.set(bytes, forKey: lastExplainRequestBytesKey)
        recordEvent("Sent /explain request")
    }

    static func recordHTTPStatus(_ status: Int) {
        UserDefaults.standard.set(status, forKey: lastHTTPStatusKey)
        touch()
    }

    static func recordBuddyImage(bytes: Int, width: Int, height: Int, ocrCharacters: Int) {
        UserDefaults.standard.set(bytes, forKey: lastBuddyImageBytesKey)
        UserDefaults.standard.set("\(width)×\(height), \(bytes) bytes", forKey: lastBuddyImageDescriptionKey)
        UserDefaults.standard.set(ocrCharacters, forKey: lastBuddyOCRCharactersKey)
        recordEvent("Captured Buddy image")
    }

    static func recordProxyMeta(model: String?, route: String?, latencyTier: String?, researchUsed: Bool?, researchProvider: String?) {
        if let model { UserDefaults.standard.set(model, forKey: lastModelKey) }
        if let route { UserDefaults.standard.set(route, forKey: lastRouteKey) }
        if let latencyTier { UserDefaults.standard.set(latencyTier, forKey: lastLatencyTierKey) }
        if let researchUsed { UserDefaults.standard.set(researchUsed, forKey: lastResearchUsedKey) }
        if let researchProvider { UserDefaults.standard.set(researchProvider, forKey: lastResearchProviderKey) }
        recordEvent("Received /explain metadata")
    }

    static func recordProxyDone(totalMs: Int?, outputCharacters: Int?, route: String?, latencyTier: String?, researchUsed: Bool?, researchProvider: String?) {
        if let totalMs { UserDefaults.standard.set(totalMs, forKey: lastTotalMsKey) }
        if let outputCharacters { UserDefaults.standard.set(outputCharacters, forKey: lastOutputCharactersKey) }
        if let route { UserDefaults.standard.set(route, forKey: lastRouteKey) }
        if let latencyTier { UserDefaults.standard.set(latencyTier, forKey: lastLatencyTierKey) }
        if let researchUsed { UserDefaults.standard.set(researchUsed, forKey: lastResearchUsedKey) }
        if let researchProvider { UserDefaults.standard.set(researchProvider, forKey: lastResearchProviderKey) }
        recordEvent("Completed /explain response")
    }

    private static func touch() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: updatedAtKey)
    }
}
