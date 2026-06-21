import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let view = SettingsView()
            .frame(width: 520, height: 360)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Lexi Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        self.init(window: window)
    }
}

private struct SettingsView: View {
    @State private var proxyURL = UserDefaults.standard.string(forKey: "LexiProxyBaseURL") ?? AppConfiguration.defaultProxyBaseURL.absoluteString
    @State private var proxyToken = UserDefaults.standard.string(forKey: "LexiProxyToken") ?? ""
    @State private var statusText = "Not checked yet."
    @State private var isCheckingStatus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Lexi Settings")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Proxy URL")
                    .font(.headline)
                TextField("Proxy URL", text: $proxyURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Proxy Token")
                    .font(.headline)
                SecureField("Proxy token", text: $proxyToken)
                    .textFieldStyle(.roundedBorder)
                Text(proxyToken.isEmpty ? "No proxy token configured." : "Proxy token configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Status")
                    .font(.headline)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            HStack {
                Button("Reset to Railway") {
                    proxyURL = "https://lexi-production-9152.up.railway.app"
                    saveSettings()
                }

                Button("Reset to Local") {
                    proxyURL = AppConfiguration.defaultProxyBaseURL.absoluteString
                    saveSettings()
                }

                Spacer()

                Button(isCheckingStatus ? "Checking…" : "Check Status") {
                    checkStatus()
                }
                .disabled(isCheckingStatus)

                Button("Save") {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
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

        statusText = "Settings saved. Restart Lexi or reopen this window before checking the new configuration."
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
                await MainActor.run {
                    statusText = "Online. Model: \(health.model). Local token: \(localTokenStatus). Backend key: \(backendKeyStatus). Backend token: \(backendTokenStatus)."
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
}
