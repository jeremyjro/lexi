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

    static var voiceAudioBufferSizeFrames: Int {
        boundedIntegerSetting(
            defaultsKey: "LexiVoiceAudioBufferSizeFrames",
            environmentKey: "LEXI_VOICE_AUDIO_BUFFER_SIZE_FRAMES",
            defaultValue: 1024,
            range: 256...4096
        )
    }

    static var assemblyAIFinalTranscriptFallbackDelaySeconds: TimeInterval {
        boundedDoubleSetting(
            defaultsKey: "LexiAssemblyAIFinalFallbackSeconds",
            environmentKey: "LEXI_ASSEMBLYAI_FINAL_FALLBACK_SECONDS",
            defaultValue: 1.2,
            range: 0.4...2.8
        )
    }

    static var voiceTokenFetchTimeoutSeconds: TimeInterval {
        boundedDoubleSetting(
            defaultsKey: "LexiVoiceTokenFetchTimeoutSeconds",
            environmentKey: "LEXI_VOICE_TOKEN_FETCH_TIMEOUT_SECONDS",
            defaultValue: 4.0,
            range: 1.0...10.0
        )
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

    private static func boundedIntegerSetting(defaultsKey: String, environmentKey: String, defaultValue: Int, range: ClosedRange<Int>) -> Int {
        let environmentValue = ProcessInfo.processInfo.environment[environmentKey].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let defaultsValue = UserDefaults.standard.object(forKey: defaultsKey) != nil ? UserDefaults.standard.integer(forKey: defaultsKey) : nil
        let value = environmentValue ?? defaultsValue ?? defaultValue
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func boundedDoubleSetting(defaultsKey: String, environmentKey: String, defaultValue: TimeInterval, range: ClosedRange<TimeInterval>) -> TimeInterval {
        let environmentValue = ProcessInfo.processInfo.environment[environmentKey].flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let defaultsValue = UserDefaults.standard.object(forKey: defaultsKey) != nil ? UserDefaults.standard.double(forKey: defaultsKey) : nil
        let value = environmentValue ?? defaultsValue ?? defaultValue
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
