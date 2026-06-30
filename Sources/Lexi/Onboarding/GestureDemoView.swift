import SwiftUI

struct GestureDemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let cycleDuration: TimeInterval = 8.0
    private let highlightPhrase = "highlight anything"
    private let streamedExplanation = "Lexi opens beside you with a calm explanation, then fades away."

    var body: some View {
        Group {
            if reduceMotion {
                staticComposition
            } else {
                TimelineView(.animation) { context in
                    animatedComposition(at: context.date)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var staticComposition: some View {
        demoShell(highlightStrength: 1, keycapStrength: 1, cardOffset: 0, cardOpacity: 1, revealedCharacters: streamedExplanation.count)
    }

    private func animatedComposition(at date: Date) -> some View {
        let phase = normalizedPhase(for: date)
        let highlightStrength = easeInOut(clamp((phase - 0.10) / 0.24))
        let keycapStrength = easeInOut(clamp((phase - 0.30) / 0.24))
        let cardStrength = easeInOut(clamp((phase - 0.52) / 0.24))
        let revealProgress = easeInOut(clamp((phase - 0.68) / 0.24))
        let revealedCharacters = max(1, Int(CGFloat(streamedExplanation.count) * revealProgress))
        let cardOffset = CGFloat(34 * (1 - cardStrength))

        return demoShell(
            highlightStrength: highlightStrength,
            keycapStrength: keycapStrength,
            cardOffset: cardOffset,
            cardOpacity: 0.30 + cardStrength * 0.70,
            revealedCharacters: revealedCharacters
        )
    }

    private func demoShell(
        highlightStrength: CGFloat,
        keycapStrength: CGFloat,
        cardOffset: CGFloat,
        cardOpacity: CGFloat,
        revealedCharacters: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            documentMock(highlightStrength: highlightStrength)
            keycapAndCard(keycapStrength: keycapStrength, cardOffset: cardOffset, cardOpacity: cardOpacity, revealedCharacters: revealedCharacters)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius, style: .continuous)
                        .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private func documentMock(highlightStrength: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("I was reading about vector clocks when I")
                .font(OnboardingTypography.body(14))
                .foregroundStyle(.primary)
            HStack(spacing: 0) {
                Text("decided to ")
                    .font(OnboardingTypography.body(14))
                    .foregroundStyle(.primary)
                Text(highlightPhrase)
                    .font(OnboardingTypography.strongBody(14))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 1.0, green: 0.88, blue: 0.72).opacity(0.50 + 0.40 * highlightStrength))
                    )
                Text(" and moved on.")
                    .font(OnboardingTypography.body(14))
                    .foregroundStyle(.primary)
            }
            Text("It felt friendly, but I still wanted the short version.")
                .font(OnboardingTypography.body(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 250, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                .fill(OnboardingPalette.surface(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                        .strokeBorder(OnboardingPalette.subtleStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private func keycapAndCard(
        keycapStrength: CGFloat,
        cardOffset: CGFloat,
        cardOpacity: CGFloat,
        revealedCharacters: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            KeycapBadge(label: "⌥ Space", strength: keycapStrength)
            explanationCard(offsetX: cardOffset, opacity: cardOpacity, revealedCharacters: revealedCharacters)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func explanationCard(offsetX: CGFloat, opacity: CGFloat, revealedCharacters: Int) -> some View {
        let prefixLength = min(streamedExplanation.count, max(1, revealedCharacters))
        let revealedText = String(streamedExplanation.prefix(prefixLength))

        return VStack(alignment: .leading, spacing: 8) {
            Text("Lexi")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(revealedText)
                .font(OnboardingTypography.body(14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: OnboardingMetrics.smallCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        .opacity(opacity)
        .offset(x: offsetX)
    }

    private func normalizedPhase(for date: Date) -> CGFloat {
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)
        return CGFloat(cycle / cycleDuration)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func easeInOut(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }
}

private struct KeycapBadge: View {
    let label: String
    let strength: CGFloat

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(OnboardingPalette.accentGradient)
            )
            .scaleEffect(1 + 0.06 * strength)
            .opacity(0.78 + 0.22 * strength)
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
    }
}
