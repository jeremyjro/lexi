import SwiftUI

struct HomeView: View {
    let isEnabled: Bool
    let onStartBuddy: () -> Void
    let onToggleEnabled: () -> Void
    let onShowWelcome: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusLine
            cheatsheet
            actions
        }
        .padding(18)
        .frame(width: 320, height: 420, alignment: .topLeading)
        .background(OnboardingPalette.background(for: colorScheme))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AppMarkView(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lexi")
                    .font(OnboardingTypography.display(24))
                    .foregroundStyle(.primary)
                Text("A calm little sidekick")
                    .font(OnboardingTypography.body(13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusLine: some View {
        Text(isEnabled ? "Listening for ⌥ Space" : "Paused")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                    .fill(OnboardingPalette.surface(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                            .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                    )
            )
    }

    private var cheatsheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            cheatRow(title: "Explain highlighted text", detail: "Hold ⌥ Space")
            cheatRow(title: "Precise Buddy", detail: "Hold ⌥⌘ and drag")
            cheatRow(title: "Quick Buddy", detail: "Hold ⌃⌥ and speak")
            cheatRow(title: "Inside an answer", detail: "Highlight + →")
        }
    }

    private func cheatRow(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(detail)
                .font(OnboardingTypography.body(13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius - 2, style: .continuous)
                .fill(OnboardingPalette.surface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius - 2, style: .continuous)
                        .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Start Buddy") {
                onStartBuddy()
            }

            Button(isEnabled ? "Pause Lexi" : "Resume Lexi") {
                onToggleEnabled()
            }

            Button("Getting started") {
                onShowWelcome()
            }

            Button("Settings…") {
                onOpenSettings()
            }

            Button("Quit Lexi") {
                onQuit()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
