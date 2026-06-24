import AVFoundation
import Speech

@MainActor
final class BuddyVoiceCapture {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private(set) var transcript = ""

    var isRecording: Bool {
        audioEngine.isRunning
    }

    func start(onTranscript: @escaping @MainActor (String) -> Void) throws {
        stopImmediately(cancelTask: true)
        transcript = ""

        guard BuddyPermissions.status(.microphone).isGranted else {
            throw BuddyVoiceCaptureError.microphonePermissionMissing
        }
        guard BuddyPermissions.status(.speechRecognition).isGranted else {
            throw BuddyVoiceCaptureError.speechPermissionMissing
        }
        guard let recognizer, recognizer.isAvailable else {
            throw BuddyVoiceCaptureError.speechUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw BuddyVoiceCaptureError.onDeviceSpeechUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    onTranscript(self.transcript)
                }
                if error != nil || result?.isFinal == true {
                    self.stopEngineOnly()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() async -> String {
        stopEngineOnly()
        recognitionRequest?.endAudio()
        try? await Task.sleep(nanoseconds: 250_000_000)
        let result = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        return result
    }

    func cancel() {
        stopImmediately(cancelTask: true)
        transcript = ""
    }

    private func stopImmediately(cancelTask: Bool) {
        stopEngineOnly()
        recognitionRequest?.endAudio()
        if cancelTask {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
        }
    }

    private func stopEngineOnly() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

enum BuddyVoiceCaptureError: LocalizedError {
    case microphonePermissionMissing
    case speechPermissionMissing
    case speechUnavailable
    case onDeviceSpeechUnavailable

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
        }
    }
}
