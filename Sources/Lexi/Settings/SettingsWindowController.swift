import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init(onStartBuddyCapture: @escaping @MainActor () -> Void = {}) {
        let view = SettingsView(onStartBuddyCapture: onStartBuddyCapture)
            .frame(width: 660, height: 720)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Lexi Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

private struct SettingsView: View {
    let onStartBuddyCapture: @MainActor () -> Void

    @State private var proxyURL = UserDefaults.standard.string(forKey: "LexiProxyBaseURL") ?? AppConfiguration.defaultProxyBaseURL.absoluteString
    @State private var proxyToken = UserDefaults.standard.string(forKey: "LexiProxyToken") ?? ""
    @State private var selectedVoiceProviderRawValue = AppConfiguration.voiceProvider.rawValue
    @State private var isReadAloudEnabled = AppConfiguration.isTTSReadAloudEnabled
    @State private var statusText = "Not checked yet."
    @State private var isCheckingStatus = false
    @State private var permissionStatuses = Dictionary(uniqueKeysWithValues: BuddyPermission.allCases.map { ($0, BuddyPermissions.status($0)) })

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                shortcutsSection
                connectionSection
                voiceSection
                statusSection
                permissionsSection
                appSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "textformat")
                .font(.system(size: 34, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Lexi Settings")
                    .font(.title2.weight(.semibold))
                Text("Configure the assistant connection, permissions, and global shortcuts.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shortcutsSection: some View {
        section("Shortcuts") {
            VStack(alignment: .leading, spacing: 10) {
                settingsRow("Explain highlighted text", "Hold Option + Space while selecting text, then release to explain")
                settingsRow("Precise Buddy", "Hold Option + Command, drag a screen region, then release the keys to ask")
                settingsRow("Quick Buddy", "Hold Control + Option, speak, then release to capture the focused window or cursor screen")
                settingsRow("Nested lookup", "Inside an answer, highlight text and press →")
                settingsRow("Close/cancel", "Esc")
                HStack {
                    Button("Start Buddy Capture") {
                        onStartBuddyCapture()
                    }
                    Spacer()
                }
            }
        }
    }

    private var connectionSection: some View {
        section("Assistant Connection") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Proxy URL")
                        .font(.headline)
                    TextField("Proxy URL", text: $proxyURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Proxy Token")
                        .font(.headline)
                    SecureField("Proxy token", text: $proxyToken)
                        .textFieldStyle(.roundedBorder)
                    Text(proxyToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No local proxy token configured." : "Local proxy token configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Reset to Local") {
                        proxyURL = AppConfiguration.defaultProxyBaseURL.absoluteString
                        saveSettings()
                    }
                    Button("Reset to Railway") {
                        proxyURL = "https://lexi-production-9152.up.railway.app"
                        saveSettings()
                    }
                    Spacer()
                    Button("Save") {
                        saveSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var voiceSection: some View {
        section("Voice and Read-Aloud") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transcription provider")
                        .font(.headline)
                    Picker("Transcription provider", selection: $selectedVoiceProviderRawValue) {
                        ForEach(LexiVoiceProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(selectedVoiceProviderRawValue == LexiVoiceProvider.assemblyAI.rawValue ? "Requires ASSEMBLYAI_API_KEY on the proxy; falls back to Apple Speech if unavailable." : "Uses local Apple Speech and requires macOS Speech Recognition permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Read answers aloud with ElevenLabs", isOn: $isReadAloudEnabled)
                Text("Read-aloud requires ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID on the proxy. It is off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                settingsRow("Voice buffer", "\(AppConfiguration.voiceAudioBufferSizeFrames) frames")
                settingsRow("AssemblyAI final fallback", "\(String(format: "%.1f", AppConfiguration.assemblyAIFinalTranscriptFallbackDelaySeconds))s")

                HStack {
                    Spacer()
                    Button("Save Voice Settings") {
                        saveSettings()
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        section("Proxy Status") {
            VStack(alignment: .leading, spacing: 10) {
                Text(statusText)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button(isCheckingStatus ? "Checking…" : "Check Status") {
                        checkStatus()
                    }
                    .disabled(isCheckingStatus)
                    Spacer()
                }
            }
        }
    }

    private var permissionsSection: some View {
        section("Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(BuddyPermission.allCases, id: \.self) { permission in
                    permissionRow(permission)
                }
                HStack {
                    Button("Re-check Permissions") {
                        refreshStatuses()
                    }
                    Spacer()
                }
            }
        }
    }

    private var appSection: some View {
        section("Installed App") {
            VStack(alignment: .leading, spacing: 10) {
                settingsRow("Bundle ID", Bundle.main.bundleIdentifier ?? "Unknown")
                settingsRow("App path", Bundle.main.bundleURL.path)
                settingsRow("Version", versionDescription)
                Text("If Screen Recording is stuck, remove Lexi from System Settings → Privacy & Security → Screen Recording, add/enable this installed app again, then quit and reopen Lexi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func settingsRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func permissionRow(_ permission: BuddyPermission) -> some View {
        let status = permissionStatuses[permission] ?? BuddyPermissions.status(permission)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status.isGranted ? .green : .orange)
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(permission.title)
                    .font(.callout.weight(.semibold))
                Text(permission.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusLabel(status))
                    .font(.caption.monospaced())
                    .foregroundStyle(status.isGranted ? .green : .orange)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if !status.isGranted {
                    Button(buttonTitle(for: permission, status: status)) {
                        BuddyPermissions.request(permission) { newStatus in
                            permissionStatuses[permission] = newStatus
                        }
                        BuddyPermissions.openSystemSettings(for: permission)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Open Settings") {
                    BuddyPermissions.openSystemSettings(for: permission)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private func statusLabel(_ status: BuddyPermissionStatus) -> String {
        switch status {
        case .granted:
            return "Enabled"
        case .denied:
            return "Denied — enable in System Settings"
        case .notDetermined:
            return "Not enabled yet"
        }
    }

    private func buttonTitle(for permission: BuddyPermission, status: BuddyPermissionStatus) -> String {
        switch status {
        case .denied:
            return "Open"
        case .granted:
            return "Enabled"
        case .notDetermined:
            return permission == .accessibility ? "Request" : "Allow"
        }
    }

    private func saveSettings() {
        let trimmedURL = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = proxyToken.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedURL.isEmpty || trimmedURL == AppConfiguration.defaultProxyBaseURL.absoluteString {
            UserDefaults.standard.removeObject(forKey: "LexiProxyBaseURL")
            proxyURL = AppConfiguration.defaultProxyBaseURL.absoluteString
        } else {
            UserDefaults.standard.set(trimmedURL, forKey: "LexiProxyBaseURL")
            proxyURL = trimmedURL
        }

        if trimmedToken.isEmpty {
            UserDefaults.standard.removeObject(forKey: "LexiProxyToken")
            proxyToken = ""
        } else {
            UserDefaults.standard.set(trimmedToken, forKey: "LexiProxyToken")
            proxyToken = trimmedToken
        }

        UserDefaults.standard.set(selectedVoiceProviderRawValue, forKey: "LexiVoiceProvider")
        UserDefaults.standard.set(isReadAloudEnabled, forKey: "LexiTTSReadAloudEnabled")
        BuddyTranscriptionProviderFactory.prewarmIfNeeded()

        statusText = "Settings saved. Check status to verify the active connection."
    }

    private func checkStatus() {
        saveSettings()
        isCheckingStatus = true
        statusText = "Checking proxy…"

        Task {
            do {
                let client = ExplainClient()
                let health = try await client.health()
                let localTokenStatus = client.hasProxyToken ? "Yes" : "No"
                let backendKeyStatus = health.anthropicApiKeyConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                let backendTokenStatus = health.proxyTokenConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                let assemblyStatus = health.assemblyAIConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                let assemblyTimeout = health.assemblyAITokenTimeoutMs.map { "\($0)ms" } ?? "Unknown"
                let elevenLabsStatus = health.elevenLabsConfigured.map { $0 ? "Yes" : "No" } ?? "Unknown"
                let diagnostics = LexiDiagnostics.snapshot.summary
                await MainActor.run {
                    statusText = """
                    Online: \(health.ok ? "Yes" : "No")
                    Text model: \(health.model)
                    Nested model: \(health.nestedModel ?? health.model)
                    Vision model: \(health.visionModel ?? health.model)
                    Body limit: \(health.jsonBodyLimit ?? "Unknown")
                    Local token: \(localTokenStatus)
                    Backend API key: \(backendKeyStatus)
                    Backend proxy token: \(backendTokenStatus)
                    AssemblyAI: \(assemblyStatus)
                    AssemblyAI token timeout: \(assemblyTimeout)
                    Voice buffer: \(AppConfiguration.voiceAudioBufferSizeFrames) frames
                    AssemblyAI final fallback: \(String(format: "%.1f", AppConfiguration.assemblyAIFinalTranscriptFallbackDelaySeconds))s
                    ElevenLabs: \(elevenLabsStatus)

                    Diagnostics:
                    \(diagnostics)
                    """
                    isCheckingStatus = false
                }
            } catch {
                await MainActor.run {
                    statusText = error.localizedDescription
                    isCheckingStatus = false
                }
            }
        }
    }

    private func refreshStatuses() {
        permissionStatuses = Dictionary(uniqueKeysWithValues: BuddyPermission.allCases.map { ($0, BuddyPermissions.status($0)) })
    }
}
