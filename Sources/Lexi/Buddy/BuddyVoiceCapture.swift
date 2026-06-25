import AVFoundation
import Speech

@MainActor
final class BuddyVoiceCapture {
    private let audioEngine = AVAudioEngine()
    private var transcriptionSession: (any BuddyStreamingTranscriptionSession)?
    private(set) var transcript = ""
    private var finalTranscriptContinuation: CheckedContinuation<String, Never>?
    private var finalTranscriptFallbackTask: Task<Void, Never>?
    private var startGeneration = UUID()

    var isRecording: Bool {
        audioEngine.isRunning
    }

    func start(keyterms: [String] = [], onTranscript: @escaping @MainActor (String) -> Void) throws {
        stopImmediately()
        transcript = ""
        let generation = UUID()
        startGeneration = generation

        guard BuddyPermissions.status(.microphone).isGranted else {
            throw BuddyVoiceCaptureError.microphonePermissionMissing
        }
        if AppConfiguration.voiceProvider == .appleSpeech {
            guard BuddyPermissions.status(.speechRecognition).isGranted else {
                throw BuddyVoiceCaptureError.speechPermissionMissing
            }
        }

        Task { @MainActor in
            guard self.startGeneration == generation else { return }
            do {
                let provider = BuddyTranscriptionProviderFactory.makeProvider()
                try await start(provider: provider, keyterms: keyterms, generation: generation, onTranscript: onTranscript)
            } catch {
                guard self.startGeneration == generation else { return }
                if AppConfiguration.voiceProvider == .assemblyAI {
                    do {
                        let provider = BuddyTranscriptionProviderFactory.makeFallbackProvider()
                        try await start(provider: provider, keyterms: keyterms, generation: generation, onTranscript: onTranscript)
                    } catch {
                        guard self.startGeneration == generation else { return }
                        finishWithError(error)
                    }
                } else {
                    finishWithError(error)
                }
            }
        }
    }

    func stop() async -> String {
        startGeneration = UUID()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        transcriptionSession?.requestFinalTranscript()

        let fallbackDelay = transcriptionSession?.finalTranscriptFallbackDelaySeconds ?? 0.35
        finalTranscriptFallbackTask?.cancel()
        finalTranscriptFallbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(fallbackDelay * 1_000_000_000))
            finishFinalTranscript(transcript)
        }

        return await withCheckedContinuation { continuation in
            finalTranscriptContinuation = continuation
        }
    }

    func cancel() {
        stopImmediately()
        transcript = ""
    }

    private func start(
        provider: any BuddyTranscriptionProvider,
        keyterms: [String],
        generation: UUID,
        onTranscript: @escaping @MainActor (String) -> Void
    ) async throws {
        let session = try await provider.startStreamingSession(
            keyterms: keyterms,
            onTranscriptUpdate: { [weak self] text in
                guard let self else { return }
                self.transcript = text
                onTranscript(text)
            },
            onFinalTranscriptReady: { [weak self] text in
                self?.finishFinalTranscript(text)
            },
            onError: { [weak self] error in
                self?.finishWithError(error)
            }
        )
        guard startGeneration == generation else {
            session.cancel()
            return
        }
        transcriptionSession = session

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.transcriptionSession?.appendAudioBuffer(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func finishFinalTranscript(_ text: String) {
        finalTranscriptFallbackTask?.cancel()
        finalTranscriptFallbackTask = nil
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = result
        finalTranscriptContinuation?.resume(returning: result)
        finalTranscriptContinuation = nil
        transcriptionSession?.cancel()
        transcriptionSession = nil
    }

    private func finishWithError(_ error: Error) {
        print("Lexi voice transcription failed: \(error.localizedDescription)")
        finishFinalTranscript(transcript)
    }

    private func stopImmediately() {
        startGeneration = UUID()
        finalTranscriptFallbackTask?.cancel()
        finalTranscriptFallbackTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        transcriptionSession?.cancel()
        transcriptionSession = nil
        finalTranscriptContinuation?.resume(returning: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        finalTranscriptContinuation = nil
    }
}

enum BuddyVoiceCaptureError: LocalizedError {
    case microphonePermissionMissing
    case speechPermissionMissing
    case speechUnavailable
    case onDeviceSpeechUnavailable
    case transcriptionProviderUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionMissing:
            return "Microphone permission is required for Buddy Capture."
        case .speechPermissionMissing:
            return "Speech Recognition permission is required for Buddy Capture."
        case .speechUnavailable:
            return "Speech recognition is unavailable right now."
        case .onDeviceSpeechUnavailable:
            return "On-device speech recognition is not available for the current locale."
        case .transcriptionProviderUnavailable(let message):
            return message
        }
    }
}
