import AVFoundation
import Foundation
import Speech

protocol BuddyStreamingTranscriptionSession: AnyObject {
    var finalTranscriptFallbackDelaySeconds: TimeInterval { get }
    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer)
    func requestFinalTranscript()
    func cancel()
}

protocol BuddyTranscriptionProvider {
    var displayName: String { get }
    var requiresSpeechRecognitionPermission: Bool { get }
    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping @MainActor (String) -> Void,
        onFinalTranscriptReady: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession
}

enum BuddyTranscriptionProviderFactory {
    static func makeProvider() -> any BuddyTranscriptionProvider {
        switch AppConfiguration.voiceProvider {
        case .assemblyAI:
            return AssemblyAITranscriptionProvider()
        case .appleSpeech:
            return AppleSpeechTranscriptionProvider()
        }
    }

    static func makeFallbackProvider() -> any BuddyTranscriptionProvider {
        AppleSpeechTranscriptionProvider()
    }
}

final class AppleSpeechTranscriptionProvider: BuddyTranscriptionProvider {
    let displayName = "Apple Speech"
    let requiresSpeechRecognitionPermission = true

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping @MainActor (String) -> Void,
        onFinalTranscriptReady: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            throw BuddyVoiceCaptureError.speechUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw BuddyVoiceCaptureError.onDeviceSpeechUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if !keyterms.isEmpty {
            request.contextualStrings = keyterms
        }
        let session = AppleSpeechTranscriptionSession(
            recognizer: recognizer,
            request: request,
            onTranscriptUpdate: onTranscriptUpdate,
            onFinalTranscriptReady: onFinalTranscriptReady,
            onError: onError
        )
        try session.start()
        return session
    }
}

private final class AppleSpeechTranscriptionSession: BuddyStreamingTranscriptionSession {
    let finalTranscriptFallbackDelaySeconds: TimeInterval = 0.35

    private let request: SFSpeechAudioBufferRecognitionRequest
    private let onTranscriptUpdate: @MainActor (String) -> Void
    private let onFinalTranscriptReady: @MainActor (String) -> Void
    private let onError: @MainActor (Error) -> Void
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcript = ""

    init(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void,
        onFinalTranscriptReady: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.request = request
        self.onTranscriptUpdate = onTranscriptUpdate
        self.onFinalTranscriptReady = onFinalTranscriptReady
        self.onError = onError
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.transcript = text
                Task { @MainActor in
                    self.onTranscriptUpdate(text)
                    if result.isFinal {
                        self.onFinalTranscriptReady(text)
                    }
                }
            }
            if let error {
                Task { @MainActor in self.onError(error) }
            }
        }
    }

    func start() throws {}

    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer) {
        request.append(audioBuffer)
    }

    func requestFinalTranscript() {
        request.endAudio()
        let text = transcript
        Task { @MainActor in
            self.onFinalTranscriptReady(text)
        }
    }

    func cancel() {
        request.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

final class AssemblyAITranscriptionProvider: BuddyTranscriptionProvider {
    let displayName = "AssemblyAI"
    let requiresSpeechRecognitionPermission = false
    private let sharedSession = URLSession(configuration: .default)

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping @MainActor (String) -> Void,
        onFinalTranscriptReady: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession {
        let token = try await fetchTemporaryToken()
        let session = AssemblyAITranscriptionSession(
            token: token,
            keyterms: keyterms,
            urlSession: sharedSession,
            onTranscriptUpdate: onTranscriptUpdate,
            onFinalTranscriptReady: onFinalTranscriptReady,
            onError: onError
        )
        try await session.open()
        return session
    }

    private func fetchTemporaryToken() async throws -> String {
        var request = URLRequest(url: AppConfiguration.current.proxyBaseURL.appendingPathComponent("transcribe-token"))
        request.httpMethod = "POST"
        if let token = AppConfiguration.current.proxyToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BuddyVoiceCaptureError.transcriptionProviderUnavailable("AssemblyAI token endpoint is unavailable.")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String,
              !token.isEmpty else {
            throw BuddyVoiceCaptureError.transcriptionProviderUnavailable("AssemblyAI token response was invalid.")
        }
        return token
    }
}

private final class AssemblyAITranscriptionSession: NSObject, BuddyStreamingTranscriptionSession, @unchecked Sendable {
    private struct Envelope: Decodable { let type: String }
    private struct Turn: Decodable {
        let transcript: String?
        let turn_order: Int?
        let end_of_turn: Bool?
        let turn_is_formatted: Bool?
    }
    private struct ErrorMessage: Decodable {
        let error: String?
        let message: String?
    }

    let finalTranscriptFallbackDelaySeconds: TimeInterval = 2.8
    private static let sampleRate = 16_000.0
    private let token: String
    private let keyterms: [String]
    private let urlSession: URLSession
    private let onTranscriptUpdate: @MainActor (String) -> Void
    private let onFinalTranscriptReady: @MainActor (String) -> Void
    private let onError: @MainActor (Error) -> Void
    private let audioConverter = BuddyPCM16AudioConverter(targetSampleRate: sampleRate)
    private let stateQueue = DispatchQueue(label: "com.lexi.assemblyai.state")
    private let sendQueue = DispatchQueue(label: "com.lexi.assemblyai.send")
    private var webSocketTask: URLSessionWebSocketTask?
    private var latestTranscript = ""
    private var activeTurnOrder: Int?
    private var activeTurnTranscript = ""
    private var storedTurnTranscriptsByOrder: [Int: String] = [:]
    private var deliveredFinal = false
    private var isAwaitingFinalTranscript = false
    private var readyContinuation: CheckedContinuation<Void, Error>?

    init(
        token: String,
        keyterms: [String],
        urlSession: URLSession,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void,
        onFinalTranscriptReady: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.token = token
        self.keyterms = keyterms
        self.urlSession = urlSession
        self.onTranscriptUpdate = onTranscriptUpdate
        self.onFinalTranscriptReady = onFinalTranscriptReady
        self.onError = onError
    }

    func open() async throws {
        let url = try websocketURL()
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        receiveNextMessage()
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { self.readyContinuation = continuation }
        }
    }

    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer) {
        guard let data = audioConverter.convertToPCM16Data(from: audioBuffer), !data.isEmpty else { return }
        sendQueue.async { [weak self] in
            self?.webSocketTask?.send(.data(data)) { error in
                if let error { self?.fail(error) }
            }
        }
    }

    func requestFinalTranscript() {
        stateQueue.sync {
            self.isAwaitingFinalTranscript = true
        }
        sendJSON(["type": "ForceEndpoint"])
        stateQueue.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.deliverFinalIfNeeded()
        }
    }

    func cancel() {
        sendJSON(["type": "Terminate"])
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handle(text) }
                @unknown default:
                    break
                }
                self.receiveNextMessage()
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        switch envelope.type.lowercased() {
        case "begin":
            resolveReady(.success(()))
        case "turn":
            if let turn = try? JSONDecoder().decode(Turn.self, from: data) {
                handleTurn(turn)
            }
        case "termination":
            resolveReady(.success(()))
            deliverFinalIfNeeded()
        case "error":
            let message = (try? JSONDecoder().decode(ErrorMessage.self, from: data)).map { $0.error ?? $0.message ?? "AssemblyAI returned an error." } ?? "AssemblyAI returned an error."
            fail(BuddyVoiceCaptureError.transcriptionProviderUnavailable(message))
        default:
            break
        }
    }

    private func handleTurn(_ turn: Turn) {
        let transcript = turn.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        stateQueue.async {
            let turnOrder = turn.turn_order ?? self.activeTurnOrder ?? ((self.storedTurnTranscriptsByOrder.keys.max() ?? -1) + 1)
            if turn.end_of_turn == true || turn.turn_is_formatted == true {
                if !transcript.isEmpty {
                    self.storedTurnTranscriptsByOrder[turnOrder] = transcript
                }
                self.activeTurnOrder = nil
                self.activeTurnTranscript = ""
            } else {
                self.activeTurnOrder = turnOrder
                self.activeTurnTranscript = transcript
            }

            let fullTranscript = self.composeTranscript()
            self.latestTranscript = fullTranscript
            if !fullTranscript.isEmpty {
                Task { @MainActor in self.onTranscriptUpdate(fullTranscript) }
            }
            if self.isAwaitingFinalTranscript && (turn.end_of_turn == true || turn.turn_is_formatted == true) {
                self.deliverFinalIfNeeded()
            }
        }
    }

    private func composeTranscript() -> String {
        var segments = storedTurnTranscriptsByOrder
            .sorted { $0.key < $1.key }
            .map(\.value)
            .filter { !$0.isEmpty }
        if !activeTurnTranscript.isEmpty {
            segments.append(activeTurnTranscript)
        }
        return segments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deliverFinalIfNeeded() {
        stateQueue.async {
            guard !self.deliveredFinal else { return }
            self.deliveredFinal = true
            let transcript = self.composeTranscript().isEmpty ? self.latestTranscript : self.composeTranscript()
            Task { @MainActor in self.onFinalTranscriptReady(transcript) }
            self.sendJSON(["type": "Terminate"])
        }
    }

    private func fail(_ error: Error) {
        resolveReady(.failure(error))
        Task { @MainActor in self.onError(error) }
    }

    private func resolveReady(_ result: Result<Void, Error>) {
        stateQueue.async {
            guard let continuation = self.readyContinuation else { return }
            self.readyContinuation = nil
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        sendQueue.async { [weak self] in
            self?.webSocketTask?.send(.string(string)) { error in
                if let error { self?.fail(error) }
            }
        }
    }

    private func websocketURL() throws -> URL {
        guard var components = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws") else {
            throw BuddyVoiceCaptureError.transcriptionProviderUnavailable("AssemblyAI websocket URL is invalid.")
        }
        var items = [
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "speech_model", value: "universal-3-5-pro"),
            URLQueryItem(name: "prompt", value: "Short push-to-talk questions about on-screen research material, software interfaces, code, charts, documents, and technical concepts."),
            URLQueryItem(name: "token", value: token)
        ]
        let normalizedKeyterms = keyterms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 50 }
            .prefix(100)
        if !normalizedKeyterms.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: Array(normalizedKeyterms)),
           let json = String(data: data, encoding: .utf8) {
            items.append(URLQueryItem(name: "keyterms_prompt", value: json))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw BuddyVoiceCaptureError.transcriptionProviderUnavailable("AssemblyAI websocket URL could not be created.")
        }
        return url
    }
}
