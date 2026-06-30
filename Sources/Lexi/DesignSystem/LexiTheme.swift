import SwiftUI
import AppKit

/// Lexi's brand & design-system foundation.
///
/// `LexiTheme` is the single source of truth for Lexi's visual identity —
/// the **Aurora** direction: warm "paper" surfaces, ink-dark text, and a
/// signature marigold→coral *spark* accent with a soft violet glow.
///
/// Everything here is additive. The semantic status colors used elsewhere in
/// the app (system green / blue / orange / purple) keep working unchanged —
/// see ``LexiTheme/Status`` for friendly, brand-tuned aliases that map onto
/// them. The brand `accent` is for selection, emphasis, links and glows; it is
/// never a replacement for status semantics.
///
/// All values are tuned for macOS 14+ and resolve correctly in light & dark
/// appearances via dynamic `NSColor` providers.
public enum LexiTheme {

    // MARK: - Spacing

    /// An 8pt-based spacing scale. Use these instead of magic numbers so every
    /// surface breathes consistently.
    public enum Spacing {
        /// 2pt — hairline gaps between tightly-coupled glyphs.
        public static let xxs: CGFloat = 2
        /// 4pt.
        public static let xs: CGFloat = 4
        /// 8pt — default gap between related controls.
        public static let sm: CGFloat = 8
        /// 12pt.
        public static let md: CGFloat = 12
        /// 16pt — default gap between rows / list items.
        public static let lg: CGFloat = 16
        /// 24pt — default container padding.
        public static let xl: CGFloat = 24
        /// 32pt — section separation.
        public static let xxl: CGFloat = 32
        /// 48pt — generous hero / empty-state breathing room.
        public static let xxxl: CGFloat = 48
    }

    // MARK: - Corner radius

    /// Continuous corner radii. Prefer `.continuous` style everywhere to match
    /// the squircle language of the app icon and macOS materials.
    public enum Radius {
        /// 6pt — chips, tags, tiny controls.
        public static let xs: CGFloat = 6
        /// 10pt — buttons, fields.
        public static let sm: CGFloat = 10
        /// 14pt — cards, rows.
        public static let md: CGFloat = 14
        /// 20pt — panels, sheets.
        public static let lg: CGFloat = 20
        /// 28pt — the floating answer panel / large surfaces.
        public static let xl: CGFloat = 28
        /// Fully rounded pill.
        public static let pill: CGFloat = 999
    }

    // MARK: - Hairline

    /// Standard hairline border width for separators and outlined surfaces.
    public static let hairline: CGFloat = 1

    // MARK: - Materials

    /// Conventional vibrancy materials for Lexi surfaces. Use these so glass
    /// surfaces feel consistent across the answer panel, popovers and sheets.
    public enum Material {
        /// The floating answer panel / Buddy overlay background.
        public static let panel: SwiftUI.Material = .ultraThinMaterial
        /// Popovers, menus and secondary floating surfaces.
        public static let popover: SwiftUI.Material = .regularMaterial
        /// Inline cards layered on an opaque window (e.g. Settings).
        public static let card: SwiftUI.Material = .thinMaterial
    }

    // MARK: - Animation

    /// Lexi's signature motion — gentle, springy, never abrupt. Use for the
    /// pill→panel transition, hover states and content reveals.
    public enum Motion {
        /// A soft spring for appearance / expansion.
        public static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
        /// A quick ease for hovers and small state changes.
        public static let quick = Animation.easeOut(duration: 0.18)
        /// A calm ease for content / opacity reveals.
        public static let reveal = Animation.easeInOut(duration: 0.28)
    }
}

// MARK: - Brand palette (Aurora)

public extension Color {

    /// Builds a light/dark dynamic SwiftUI color from two sRGB hex values.
    static func lexiDynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(srgbHex: isDark ? dark : light)
        })
    }

    // -- Signature accent (the "spark") -------------------------------------

    /// Lexi's primary brand accent — a warm marigold. Use for selection,
    /// emphasis, focus rings, active states and the brand glow.
    ///
    /// > Note: amber is intentionally low-contrast on white. For *text* and
    /// > *links* on light surfaces use ``Color/lexiAccentText`` instead, which
    /// > is the AA-compliant deepened tone.
    static let lexiAccent = Color.lexiDynamic(light: 0xF2A03D, dark: 0xFFB45C)

    /// AA-compliant accent for text and links (deepened marigold). Pairs with
    /// ``Color/lexiAccent`` for accent-colored labels on light & dark paper.
    static let lexiAccentText = Color.lexiDynamic(light: 0xB5650C, dark: 0xFFC988)

    /// Secondary brand accent — coral. Used as the warm end of brand gradients
    /// (icon, hero glows) and for playful highlights.
    static let lexiCoral = Color.lexiDynamic(light: 0xFF6B6B, dark: 0xFF7E7E)

    /// Tertiary brand hue — a soft violet glow that grounds the warm accents
    /// and ties back to Lexi's "magical" feel. Mostly used in gradients.
    static let lexiViolet = Color.lexiDynamic(light: 0x7C5CFF, dark: 0x9B82FF)

    // -- Surfaces (warm "paper") --------------------------------------------

    /// Primary surface — warm cream paper (light) / warm charcoal (dark).
    static let lexiPaper = Color.lexiDynamic(light: 0xF7F2E9, dark: 0x1A1714)

    /// Elevated surface — cards, rows, fields raised above ``Color/lexiPaper``.
    static let lexiPaperElevated = Color.lexiDynamic(light: 0xFFFDF8, dark: 0x241F1A)

    /// Sunken / inset surface — wells, code blocks, track backgrounds.
    static let lexiPaperSunken = Color.lexiDynamic(light: 0xEFE8D9, dark: 0x141110)

    // -- Ink (text) ----------------------------------------------------------

    /// Primary text — warm near-black ink (light) / warm off-white (dark).
    static let lexiInk = Color.lexiDynamic(light: 0x1F1B16, dark: 0xF3EEE6)

    /// Secondary text — captions, supporting copy.
    static let lexiInkSecondary = Color.lexiDynamic(light: 0x6B6258, dark: 0xB8AE9F)

    /// Tertiary text — the faintest labels, placeholders, footnote numerals.
    static let lexiInkTertiary = Color.lexiDynamic(light: 0x9A9082, dark: 0x847A6C)

    // -- Lines ---------------------------------------------------------------

    /// Hairline borders and separators on paper surfaces.
    static let lexiHairline = Color.lexiDynamic(light: 0xE7DECB, dark: 0x3A332B)

    /// A subtle tinted wash of the accent — for selected rows, accent chips and
    /// hover fills. Low alpha so it layers on any surface.
    static let lexiAccentWash = Color.lexiDynamic(light: 0xF2A03D, dark: 0xFFB45C).opacity(0.12)
}

// MARK: - Brand gradients

public extension LinearGradient {

    /// The signature Aurora gradient (marigold → coral → violet glow). Used by
    /// the app icon, hero washes and the brand mark badge.
    static let lexiAurora = LinearGradient(
        colors: [.lexiAccent, .lexiCoral, .lexiViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A subtler two-stop warm gradient for buttons and small accents.
    static let lexiWarm = LinearGradient(
        colors: [.lexiAccent, .lexiCoral],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Type scale

public extension Font {

    /// Lexi's display face — SF Serif, bold. This is the brand voice: warm,
    /// literary, human. Reserve it for the wordmark and large hero titles.
    static func lexiDisplay(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    /// Largest UI title (rounded SF) — header titles.
    static let lexiTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
    /// Section title.
    static let lexiTitle2 = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// Emphasis / row title.
    static let lexiHeadline = Font.system(size: 15, weight: .semibold)
    /// Default body copy.
    static let lexiBody = Font.system(size: 13, weight: .regular)
    /// Supporting body / secondary copy.
    static let lexiCallout = Font.system(size: 13, weight: .regular)
    /// Small supporting label.
    static let lexiSubheadline = Font.system(size: 12, weight: .regular)
    /// Caption — metadata, hints.
    static let lexiCaption = Font.system(size: 11, weight: .regular)
    /// Smallest footnote — source attributions, footnote numerals.
    static let lexiFootnote = Font.system(size: 10, weight: .regular)
}

// MARK: - Status (semantic) colors

public extension LexiTheme {

    /// Brand-tuned aliases for the semantic status colors already used across
    /// the app. These intentionally map onto the system colors so existing
    /// `.green` / `.blue` / `.orange` / `.purple` usages stay visually
    /// compatible — adopt these names for clarity, not for a different look.
    enum Status {
        /// Granted / connected / done. (system green)
        public static let success = Color.green
        /// Informational / in-progress. (system blue)
        public static let info = Color.blue
        /// Needs attention / pending permission. (system orange)
        public static let warning = Color.orange
        /// Error / failure. (system red)
        public static let error = Color.red
        /// Special / research / nested-lookup. (system purple)
        public static let special = Color.purple
    }
}

// MARK: - View modifiers

public extension View {

    /// Styles a view as a Lexi "card": elevated paper surface, continuous
    /// corner radius and a hairline border. Use for grouped settings sections
    /// and content blocks.
    func lexiCard(
        padding: CGFloat = LexiTheme.Spacing.lg,
        radius: CGFloat = LexiTheme.Radius.md
    ) -> some View {
        self
            .padding(padding)
            .background(Color.lexiPaperElevated, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.lexiHairline, lineWidth: LexiTheme.hairline)
            )
    }

    /// Applies Lexi's brand accent tint to interactive controls (buttons,
    /// toggles, pickers) in one call.
    func lexiAccented() -> some View {
        self.tint(.lexiAccent)
    }

    /// Adds the signature warm Aurora glow behind a view — used sparingly for
    /// the brand mark and key focal points.
    func lexiGlow(radius: CGFloat = 18, opacity: Double = 0.35) -> some View {
        self.shadow(color: Color.lexiAccent.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}

// MARK: - Primary button style

/// Lexi's primary call-to-action button — a warm pill with the Aurora gradient
/// and a gentle press spring. Use for the single most important action on a
/// surface (e.g. "Ask", "Start Buddy Capture", "Get Started").
public struct LexiPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lexiHeadline)
            .foregroundStyle(.white)
            .padding(.horizontal, LexiTheme.Spacing.lg)
            .padding(.vertical, LexiTheme.Spacing.sm)
            .background(LinearGradient.lexiWarm, in: Capsule(style: .continuous))
            .lexiGlow(radius: 14, opacity: configuration.isPressed ? 0.20 : 0.40)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(LexiTheme.Motion.quick, value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == LexiPrimaryButtonStyle {
    /// Lexi's primary, warm pill call-to-action style.
    static var lexiPrimary: LexiPrimaryButtonStyle { LexiPrimaryButtonStyle() }
}

// MARK: - NSColor hex helper

extension NSColor {
    /// Creates an opaque `NSColor` from a 24-bit RGB hex value in the sRGB
    /// color space (e.g. `0xF2A03D`).
    convenience init(srgbHex hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
