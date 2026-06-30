import SwiftUI

/// Lightweight design language for the Settings window.
///
/// The goal is a calm, warm, productized feel (à la Poke / Devin) rather than a
/// developer console: generous spacing, a clear hierarchy, friendly copy, and a
/// single restrained accent drawn from the shared Lexi brand tokens
/// (`Color.lexiAccent`).
enum SettingsTheme {
    static let accent = Color.lexiAccent

    enum Spacing {
        static let section: CGFloat = 24
        static let card: CGFloat = 18
        static let row: CGFloat = 12
        static let tight: CGFloat = 6
    }

    enum Radius {
        static let card: CGFloat = 16
        static let chip: CGFloat = 8
        static let inner: CGFloat = 10
    }
}

/// A small uppercase "eyebrow" label that introduces a group, giving the page an
/// editorial rhythm instead of a stack of identical headings.
struct SettingsEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

/// A titled content group. `prominent` cards get a soft accent-tinted background
/// so the things that matter (shortcuts) read louder than the rest.
struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var prominent: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.Spacing.card) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(prominent ? SettingsTheme.accent : Color.secondary)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(SettingsTheme.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTheme.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(prominent ? 0.06 : 0.05), lineWidth: 1)
        )
    }

    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsTheme.Radius.card, style: .continuous)
        if prominent {
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(SettingsTheme.accent.opacity(0.06))
            }
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

/// A keyboard glyph rendered as a soft key cap, used by the shortcuts cheatsheet.
struct Keycap: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minWidth: 22)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.Radius.chip, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.Radius.chip, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// One line of the shortcuts cheatsheet: a friendly name + description on the
/// left, the key caps on the right.
struct ShortcutRow: View {
    let title: String
    let detail: String
    /// Each entry is either a key cap symbol or, when `isPlus` is true, a "+" joiner.
    let keys: [ShortcutKey]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    switch key {
                    case .cap(let symbol):
                        Keycap(symbol: symbol)
                    case .plus:
                        Text("+")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.top, 1)
        }
    }
}

enum ShortcutKey {
    case cap(String)
    case plus

    /// Convenience builder: `ShortcutKey.combo("⌥", "Space")` → ⌥ + Space.
    static func combo(_ symbols: String...) -> [ShortcutKey] {
        var result: [ShortcutKey] = []
        for (index, symbol) in symbols.enumerated() {
            if index > 0 { result.append(.plus) }
            result.append(.cap(symbol))
        }
        return result
    }
}

/// A colored dot + human status line ("Connected", "Can't reach Lexi"). Replaces
/// the old monospaced diagnostics dump as the default-visible health indicator.
struct StatusPill: View {
    let color: Color
    let text: String
    var animatesPulse: Bool = false

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .opacity(animatesPulse && isPulsing ? 0.35 : 1)
                .animation(
                    animatesPulse
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .onAppear { isPulsing = animatesPulse }
        .onChange(of: animatesPulse) { isPulsing = $0 }
    }
}

/// Small inline "Needs setup" badge shown next to a capability that isn't
/// available yet, so we surface limitations in user terms instead of leaking
/// API-key names into the primary copy.
struct NeedsSetupBadge: View {
    var label: String = "Needs setup"

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.orange.opacity(0.16))
            )
            .foregroundStyle(.orange)
    }
}
