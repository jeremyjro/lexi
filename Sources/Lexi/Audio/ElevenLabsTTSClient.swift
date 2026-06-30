import AVFoundation
import Foundation

@MainActor
final class ElevenLabsTTSClient {
    private var audioPlayer: AVAudioPlayer?
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    func speak(_ text: String, configuration: AppConfiguration = .current) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, configuration.isReadAloudEnabled else { return }

        var request = URLRequest(url: configuration.proxyBaseURL.appendingPathComponent("tts"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        if let token = configuration.proxyToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": trimmed,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ])

        let (data, response) = try await Self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ExplainClientError.proxyError(code: "tts_unavailable", message: "Lexi read-aloud is unavailable. Check ElevenLabs settings on the proxy.")
        }
        let player = try AVAudioPlayer(data: data)
        audioPlayer = player
        player.play()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
