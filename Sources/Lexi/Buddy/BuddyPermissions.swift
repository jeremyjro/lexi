import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech

/// The macOS permissions Lexi needs. V1 needs only Accessibility; the buddy
/// (Feature 4) adds Screen Recording, Microphone, and Speech Recognition.
enum BuddyPermission: CaseIterable, Hashable {
    case accessibility
    case screenRecording
    case microphone
    case speechRecognition

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .microphone: return "Microphone"
        case .speechRecognition: return "Speech Recognition"
        }
    }

    var rationale: String {
        switch self {
        case .accessibility: return "Read highlighted text and run global hotkeys."
        case .screenRecording: return "Capture the region you drag with the buddy."
        case .microphone: return "Hear your spoken question while you hold the key."
        case .speechRecognition: return "Transcribe your question on-device."
        }
    }

    var systemSettingsURL: URL? {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .microphone: anchor = "Privacy_Microphone"
        case .speechRecognition: anchor = "Privacy_SpeechRecognition"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

enum BuddyPermissionStatus {
    case granted
    case denied
    case notDetermined

    var isGranted: Bool { self == .granted }
}

/// Thin wrapper over the four TCC checks. Each request is just-in-time and has a
/// re-check path, mirroring the existing Accessibility onboarding flow.
enum BuddyPermissions {
    static func status(_ permission: BuddyPermission) -> BuddyPermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        }
    }

    static var allGranted: Bool {
        requiredPermissions.allSatisfy { status($0).isGranted }
    }

    static var requiredPermissions: [BuddyPermission] {
        var permissions: [BuddyPermission] = [.accessibility, .screenRecording, .microphone]
        if AppConfiguration.voiceProvider == .appleSpeech {
            permissions.append(.speechRecognition)
        }
        return permissions
    }

    /// Permissions the buddy gesture needs to function (everything except the
    /// V1-only Accessibility check, which has its own dedicated flow).
    static var buddyReady: Bool {
        requiredPermissions.filter { $0 != .accessibility }.allSatisfy { status($0).isGranted }
    }

    static func request(_ permission: BuddyPermission, completion: @escaping (BuddyPermissionStatus) -> Void) {
        switch permission {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            deliver(status(.accessibility), to: completion)
        case .screenRecording:
            // Triggers the system prompt the first time; subsequent calls are no-ops.
            DispatchQueue.global(qos: .userInitiated).async {
                let granted = CGRequestScreenCaptureAccess()
                deliver(granted ? .granted : .denied, to: completion)
            }
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                deliver(granted ? .granted : .denied, to: completion)
            }
        case .speechRecognition:
            SFSpeechRecognizer.requestAuthorization { authStatus in
                let mapped: BuddyPermissionStatus
                switch authStatus {
                case .authorized: mapped = .granted
                case .denied, .restricted: mapped = .denied
                case .notDetermined: mapped = .notDetermined
                @unknown default: mapped = .notDetermined
                }
                deliver(mapped, to: completion)
            }
        }
    }

    static func openSystemSettings(for permission: BuddyPermission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private static func deliver(_ status: BuddyPermissionStatus, to completion: @escaping (BuddyPermissionStatus) -> Void) {
        if Thread.isMainThread {
            completion(status)
        } else {
            DispatchQueue.main.async { completion(status) }
        }
    }
}
