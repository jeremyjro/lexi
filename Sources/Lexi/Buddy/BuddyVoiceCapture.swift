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
    private var captureStartedAt: CFAbsoluteTime = 0
    private var stopRequestedAt: CFAbsoluteTime = 0
    private var hasLoggedFirstPartial = false

    var isRecording: Bool {
        audioEngine.isRunning
    }

    func start(keyterms: [String] = [], onTranscript: @escaping @MainActor (String) -> Void) throws {
        stopImmediately()
        transcript = ""
        captureStartedAt = CFAbsoluteTimeGetCurrent()
        stopRequestedAt = 0
        hasLoggedFirstPartial = false
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
                if AppConfiguration.voiceProvider == .assemblyAI,
                   BuddyPermissions.status(.speechRecognition).isGranted {
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
        stopRequestedAt = CFAbsoluteTimeGetCurrent()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        transcriptionSession?.requestFinalTranscript()

        let fallbackDelay = transcriptionSession?.finalTranscriptFallbackDelaySeconds ?? 0.35
        print("Lexi voice stop requested providerFallback=\(String(format: "%.2f", fallbackDelay))s transcriptChars=\(transcript.count)")
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
        print("Lexi voice provider starting provider=\(provider.displayName) keyterms=\(keyterms.count)")
        let session = try await provider.startStreamingSession(
            keyterms: keyterms,
            onTranscriptUpdate: { [weak self] text in
                guard let self else { return }
                if !text.isEmpty && !self.hasLoggedFirstPartial {
                    self.hasLoggedFirstPartial = true
                    print("Lexi voice first partial provider=\(provider.displayName) elapsed=\(self.elapsedMsSinceCaptureStart())ms chars=\(text.count)")
                }
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
        print("Lexi voice provider ready provider=\(provider.displayName) elapsed=\(elapsedMsSinceCaptureStart())ms")
        transcriptionSession = session

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let bufferSize = AVAudioFrameCount(AppConfiguration.voiceAudioBufferSizeFrames)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.transcriptionSession?.appendAudioBuffer(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        print("Lexi voice audio engine started provider=\(provider.displayName) bufferFrames=\(bufferSize) sampleRate=\(Int(format.sampleRate)) elapsed=\(elapsedMsSinceCaptureStart())ms")
    }

    private func finishFinalTranscript(_ text: String) {
        finalTranscriptFallbackTask?.cancel()
        finalTranscriptFallbackTask = nil
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = result
        if stopRequestedAt > 0 {
            print("Lexi voice final transcript stopToFinal=\(elapsedMs(since: stopRequestedAt))ms total=\(elapsedMsSinceCaptureStart())ms chars=\(result.count)")
        }
        finalTranscriptContinuation?.resume(returning: result)
        finalTranscriptContinuation = nil
        transcriptionSession?.cancel()
        transcriptionSession = nil
    }

    private func finishWithError(_ error: Error) {
        print("Lexi voice transcription failed: \(error.localizedDescription)")
        finishFinalTranscript(transcript)
    }

    private func elapsedMsSinceCaptureStart() -> Int {
        elapsedMs(since: captureStartedAt)
    }

    private func elapsedMs(since start: CFAbsoluteTime) -> Int {
        guard start > 0 else { return 0 }
        return Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
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
