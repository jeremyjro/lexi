import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init(onStartBuddyCapture: @escaping @MainActor () -> Void = {}) {
        let view = SettingsView(onStartBuddyCapture: onStartBuddyCapture)
            .frame(width: 720, height: 780)
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
    @State private var permissionStatuses = Dictionary(uniqueKeysWithValues: BuddyPermission.allCases.map { ($0, BuddyPermissions.status($0)) })
    @State private var showAdvanced = false
    @State private var connectionState: ConnectionState = .unknown
    @State private var diagnosticsDetails = "Not checked yet."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.section) {
                header

                SettingsEyebrow(text: "Quick guide")
                shortcutsCard

                SettingsEyebrow(text: "Voice")
                voiceCard

                SettingsEyebrow(text: "Permissions")
                permissionsCard

                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: SettingsTheme.Spacing.section) {
                        advancedConnectionCard
                        advancedStatusCard
                        advancedAboutCard
                    }
                    .padding(.top, SettingsTheme.Spacing.section)
                } label: {
                    Text("Advanced")
                        .font(.headline)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            refreshStatuses()
            checkStatus()
        }
        .onChange(of: selectedVoiceProviderRawValue) { _ in
            saveSettings()
        }
        .onChange(of: isReadAloudEnabled) { _ in
            saveSettings()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                LexiWordmark(size: 30, layout: .badgeAndWordmark)
                Text("Your reading companion.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            StatusPill(color: headerStatusColor, text: headerStatusText, animatesPulse: headerStatusPulses)
        }
    }

    private var shortcutsCard: some View {
        SettingsCard(
            title: "Shortcuts",
            subtitle: "The hold-to-ask gestures and the quick nested lookup trick.",
            systemImage: "command",
            prominent: true
        ) {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.row) {
                ShortcutRow(
                    title: "Explain what you’re reading",
                    detail: "Hold the keys, highlight any text, release",
                    keys: ShortcutKey.combo("⌥", "Space")
                )
                ShortcutRow(
                    title: "Precise Buddy",
                    detail: "Hold, drag a region on screen, release to ask",
                    keys: ShortcutKey.combo("⌥", "⌘")
                )
                ShortcutRow(
                    title: "Quick Buddy",
                    detail: "Hold, speak your question, release",
                    keys: ShortcutKey.combo("⌃", "⌥")
                )
                ShortcutRow(
                    title: "Nested look-up",
                    detail: "Inside an answer, highlight a word and press →",
                    keys: ShortcutKey.combo("→")
                )
                ShortcutRow(
                    title: "Dismiss",
                    detail: "Close the panel or cancel anytime",
                    keys: ShortcutKey.combo("esc")
                )

                HStack {
                    Button("Try it now") {
                        onStartBuddyCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
        }
    }

    private var voiceCard: some View {
        SettingsCard(
            title: "Voice questions",
            subtitle: "Choose how Lexi listens when you ask by voice, and whether it reads answers back.",
            systemImage: "waveform"
        ) {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.row) {
                VStack(alignment: .leading, spacing: SettingsTheme.Spacing.tight) {
                    Picker("Voice questions provider", selection: $selectedVoiceProviderRawValue) {
                        ForEach(LexiVoiceProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(voiceProviderHelperText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Read answers aloud", isOn: $isReadAloudEnabled)
                Text("Lexi can speak answers after it finishes reasoning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionsCard: some View {
        SettingsCard(
            title: "Permissions",
            subtitle: "Grant the system access Lexi needs to watch, capture, and speak on your Mac.",
            systemImage: "lock.shield"
        ) {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.row) {
                ForEach(BuddyPermission.allCases, id: \.self) { permission in
                    permissionRow(permission)
                }

                HStack {
                    Button("Re-check") {
                        refreshStatuses()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
        }
    }

    private var advancedConnectionCard: some View {
        SettingsCard(
            title: "Connection",
            subtitle: "Point Lexi at the server you want to use.",
            systemImage: "network"
        ) {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.row) {
                VStack(alignment: .leading, spacing: SettingsTheme.Spacing.tight) {
                    Text("Server address")
                        .font(.callout.weight(.semibold))
                    TextField("Server address", text: $proxyURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: SettingsTheme.Spacing.tight) {
                    Text("Access key")
                        .font(.callout.weight(.semibold))
                    SecureField("Access key", text: $proxyToken)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Button("Use the built-in server") {
                        proxyURL = AppConfiguration.defaultProxyBaseURL.absoluteString
                        saveSettings()
                    }

                    Button("Use the hosted server") {
                        proxyURL = "https://lexi-production-9152.up.railway.app"
                        saveSettings()
                    }

                    Spacer(minLength: 0)

                    Button("Save") {
                        saveSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var advancedStatusCard: some View {
        SettingsCard(
            title: "Status / health",
            subtitle: "Copy the raw diagnostics when something needs a closer look.",
            systemImage: "stethoscope"
        ) {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.row) {
                HStack {
                    StatusPill(color: headerStatusColor, text: headerStatusText, animatesPulse: headerStatusPulses)
                    Spacer(minLength: 0)
                    Button("Copy details") {
                        copyDiagnosticsDetails()
                    }
                    Button(connectionState == .checking ? "Checking…" : "Check again") {
                        checkStatus()
                    }
                    .disabled(connectionState == .checking)
                }

                Text(diagnosticsDetails)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var advancedAboutCard: some View {
        SettingsCard(
            title: "About this app",
            subtitle: "The installed bundle, version, and a quick Screen Recording recovery note.",
            systemImage: "info.circle"
        ) {
            VStack(alignment: .leading, spacing: SettingsTheme.Spacing.row) {
                settingsRow("Bundle ID", Bundle.main.bundleIdentifier ?? "Unknown")
                settingsRow("App path", Bundle.main.bundleURL.path)
                settingsRow("Version", versionDescription)

                Text("If Screen Recording is stuck, remove Lexi from System Settings → Privacy & Security → Screen Recording, add and enable this installed app again, then quit and reopen Lexi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerStatusColor: Color {
        switch connectionState {
        case .unknown:
            return .secondary
        case .checking:
            return .blue
        case .connected:
            return .green
        case .unreachable:
            return .orange
        }
    }

    private var headerStatusText: String {
        switch connectionState {
        case .unknown, .checking:
            return "Checking…"
        case .connected:
            return "Connected"
        case .unreachable:
            return "Can't reach Lexi"
        }
    }

    private var headerStatusPulses: Bool {
        connectionState == .checking
    }

    private var voiceProvider: LexiVoiceProvider {
        LexiVoiceProvider(rawValue: selectedVoiceProviderRawValue) ?? .appleSpeech
    }

    private var voiceProviderHelperText: String {
        switch voiceProvider {
        case .assemblyAI:
            return "Higher-accuracy transcription. Falls back to on-device if it’s unavailable."
        case .appleSpeech:
            return "Transcribes on your Mac. Needs Speech Recognition permission."
        }
    }

    private func copyDiagnosticsDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsDetails, forType: .string)
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

            Spacer(minLength: 12)

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
    }

    private func checkStatus() {
        saveSettings()
        connectionState = .checking

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
                let details = """
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

                await MainActor.run {
                    connectionState = health.ok ? .connected : .unreachable
                    diagnosticsDetails = details
                }
            } catch {
                await MainActor.run {
                    connectionState = .unreachable
                    diagnosticsDetails = error.localizedDescription
                }
            }
        }
    }

    private func refreshStatuses() {
        permissionStatuses = Dictionary(uniqueKeysWithValues: BuddyPermission.allCases.map { ($0, BuddyPermissions.status($0)) })
    }

    private enum ConnectionState: Equatable {
        case unknown
        case checking
        case connected
        case unreachable
    }
}
