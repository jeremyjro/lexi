import Foundation

enum LexiVoiceProvider: String, CaseIterable, Identifiable {
    case appleSpeech = "apple"
    case assemblyAI = "assemblyai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        case .assemblyAI:
            return "AssemblyAI"
        }
    }
}

struct AppConfiguration {
    static let defaultProxyBaseURL = URL(string: "http://127.0.0.1:8787")!

    let proxyBaseURL: URL
    let proxyToken: String?
    let isReadAloudEnabled: Bool

    static var current: AppConfiguration {
        AppConfiguration(proxyBaseURL: resolvedProxyBaseURL(), proxyToken: resolvedProxyToken(), isReadAloudEnabled: isTTSReadAloudEnabled)
    }

    static var voiceProvider: LexiVoiceProvider {
        let rawValue = UserDefaults.standard.string(forKey: "LexiVoiceProvider") ?? ProcessInfo.processInfo.environment["LEXI_VOICE_PROVIDER"] ?? LexiVoiceProvider.appleSpeech.rawValue
        return LexiVoiceProvider(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .appleSpeech
    }

    static var isTTSReadAloudEnabled: Bool {
        if let environmentValue = ProcessInfo.processInfo.environment["LEXI_TTS_READ_ALOUD"], !environmentValue.isEmpty {
            return ["1", "true", "yes", "on"].contains(environmentValue.lowercased())
        }
        return UserDefaults.standard.bool(forKey: "LexiTTSReadAloudEnabled")
    }

    private static func resolvedProxyBaseURL() -> URL {
        let defaultsValue = UserDefaults.standard.string(forKey: "LexiProxyBaseURL")
        let environmentValue = ProcessInfo.processInfo.environment["LEXI_PROXY_BASE_URL"]
        let rawValue = [defaultsValue, environmentValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let rawValue, let url = URL(string: rawValue), url.scheme != nil, url.host != nil else {
            return defaultProxyBaseURL
        }

        return url
    }

    private static func resolvedProxyToken() -> String? {
        let defaultsValue = UserDefaults.standard.string(forKey: "LexiProxyToken")
        let environmentValue = ProcessInfo.processInfo.environment["LEXI_PROXY_TOKEN"]
        return [defaultsValue, environmentValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
