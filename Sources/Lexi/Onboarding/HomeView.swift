import SwiftUI

struct HomeView: View {
    let isEnabled: Bool
    let onStartBuddy: () -> Void
    let onToggleEnabled: () -> Void
    let onShowWelcome: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusBlock
            actionsGroup
            buddyModesGroup
            footer
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .background(OnboardingPalette.background(for: colorScheme))
        .onAppear {
            guard !reduceMotion else { return }
            pulse = true
        }
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
            Spacer(minLength: 0)
        }
    }

    private var statusBlock: some View {
        Button(action: onToggleEnabled) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    if isEnabled {
                        Circle()
                            .fill(Color.lexiAccent)
                            .frame(width: 10, height: 10)
                            .shadow(color: Color.lexiAccent.opacity(reduceMotion ? 0 : 0.25), radius: reduceMotion ? 0 : (pulse ? 10 : 4), x: 0, y: 0)
                            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.3 : 1.0))
                            .opacity(reduceMotion ? 1 : (pulse ? 0.9 : 0.65))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: pulse)
                    } else {
                        Circle()
                            .fill(Color.lexiInkTertiary.opacity(0.85))
                            .frame(width: 10, height: 10)
                    }
                    Circle()
                        .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                        .frame(width: 16, height: 16)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isEnabled ? "Listening" : "Paused")
                        .font(OnboardingTypography.strongBody(15))
                        .foregroundStyle(.primary)
                    Text("Wake key: ⌥ Space")
                        .font(OnboardingTypography.body(13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                    .fill(OnboardingPalette.surface(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                            .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEnabled ? "Listening, tap to pause" : "Paused, tap to resume")
    }

    private var actionsGroup: some View {
        sectionCard(title: "Actions", spacing: 8, emphasized: false) {
            menuRow(
                title: "Explain highlighted text",
                detail: "Hold ⌥ Space",
                isPrimary: false,
                action: nil
            )
            menuRow(
                title: "Inside an answer",
                detail: "Highlight →",
                isPrimary: false,
                action: nil
            )
        }
    }

    private var buddyModesGroup: some View {
        sectionCard(title: "Buddy modes", spacing: 8, emphasized: true) {
            menuRow(
                title: "Precise Buddy — drag a region to focus on",
                detail: "⌥⌘ drag",
                isPrimary: false,
                action: onStartBuddy
            )
            menuRow(
                title: "Quick Buddy — hold & talk, hands-free",
                detail: "⌃⌥",
                isPrimary: false,
                action: onStartBuddy
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onStartBuddy) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Start Buddy")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LexiPrimaryButtonStyle())

            HStack(spacing: 8) {
                footerButton(title: "Getting started", action: onShowWelcome)
                footerButton(title: isEnabled ? "Pause Lexi" : "Resume Lexi", action: onToggleEnabled)
            }

            HStack(spacing: 8) {
                footerButton(title: "Settings…", action: onOpenSettings)
                footerButton(title: "Quit Lexi", action: onQuit)
            }
        }
    }

    private func sectionCard<Content: View>(title: String, spacing: CGFloat, emphasized: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                .fill(emphasized ? OnboardingPalette.mutedSurface(for: colorScheme) : OnboardingPalette.surface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                        .strokeBorder(emphasized ? Color.lexiAccent.opacity(0.18) : OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private func menuRow(title: String, detail: String, isPrimary: Bool, action: (() -> Void)?) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    menuRowLabel(title: title, detail: detail, isPrimary: isPrimary)
                }
                .buttonStyle(.plain)
            } else {
                menuRowLabel(title: title, detail: detail, isPrimary: isPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius - 2, style: .continuous)
                .fill(isPrimary ? Color.lexiAccent.opacity(0.12) : OnboardingPalette.mutedSurface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius - 2, style: .continuous)
                        .strokeBorder(isPrimary ? Color.lexiAccent.opacity(0.20) : OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius - 2, style: .continuous))
    }

    private func menuRowLabel(title: String, detail: String, isPrimary: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OnboardingTypography.strongBody(13.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Text(detail)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05), in: Capsule(style: .continuous))
        }
    }

    private func footerButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OnboardingTypography.body(12.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius - 2, style: .continuous)
                        .fill(OnboardingPalette.mutedSurface(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius - 2, style: .continuous)
                                .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
