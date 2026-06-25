import Foundation

struct LexiDiagnosticsSnapshot {
    let lastEvent: String
    let lastExplainRequestBytes: Int
    let lastHTTPStatus: Int
    let lastBuddyImageBytes: Int
    let lastBuddyImageDescription: String
    let lastBuddyOCRCharacters: Int
    let updatedAt: Date?

    var summary: String {
        let formatter = ISO8601DateFormatter()
        return """
        Last event: \(lastEvent)
        Last /explain bytes: \(lastExplainRequestBytes == 0 ? "Unknown" : "\(lastExplainRequestBytes)")
        Last HTTP status: \(lastHTTPStatus == 0 ? "Unknown" : "\(lastHTTPStatus)")
        Last Buddy image: \(lastBuddyImageDescription.isEmpty ? "Unknown" : lastBuddyImageDescription)
        Last Buddy OCR chars: \(lastBuddyOCRCharacters == 0 ? "None/unknown" : "\(lastBuddyOCRCharacters)")
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

    private static func touch() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: updatedAtKey)
    }
}
