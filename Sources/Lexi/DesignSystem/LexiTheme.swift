import SwiftUI
import AppKit

/// Lexi's brand & design-system foundation.
///
/// `LexiTheme` is the single source of truth for Lexi's visual identity —
/// a **warm + restrained** direction: warm "paper" surfaces, ink-dark text,
/// and a single restrained warm (marigold/amber) accent. Warmth from the
/// neutrals and serif voice; restraint from one accent, generous whitespace
/// and subtle depth.
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

    /// A deeper amber, used only as the far end of the subtle single-hue warm
    /// gradient on the app icon / brand mark. It is **not** a second brand
    /// color — Lexi deliberately ships one restrained warm accent.
    static let lexiAccentDeep = Color.lexiDynamic(light: 0xE07F22, dark: 0xE89A45)

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

// MARK: - AppKit color bridge

/// Dynamic `NSColor` equivalents of the core brand tokens, for the AppKit
/// surfaces that can't take a SwiftUI `Color` — chiefly the `NSTextView`-backed
/// Markdown renderer in the answer panel and the menu-bar home window.
public extension NSColor {

    /// Builds a light/dark dynamic `NSColor` from two sRGB hex values.
    static func lexiDynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(srgbHex: isDark ? dark : light)
        }
    }

    /// Brand accent — matches ``SwiftUI/Color/lexiAccent``.
    static let lexiAccent = NSColor.lexiDynamic(light: 0xF2A03D, dark: 0xFFB45C)

    /// AA-compliant accent for links and small emphasis on paper — matches
    /// ``SwiftUI/Color/lexiAccentText``.
    static let lexiAccentText = NSColor.lexiDynamic(light: 0xB5650C, dark: 0xFFC988)

    /// Primary warm paper surface — matches ``SwiftUI/Color/lexiPaper``.
    static let lexiPaper = NSColor.lexiDynamic(light: 0xF7F2E9, dark: 0x1A1714)
}

// MARK: - Brand gradients

public extension LinearGradient {

    /// Lexi's single, restrained warm gradient — a gentle marigold → deeper
    /// amber within one hue family. Reserved for the app icon and brand mark.
    /// In UI chrome, prefer the **solid** ``Color/lexiAccent`` over a gradient
    /// to keep surfaces calm.
    static let lexiWarm = LinearGradient(
        colors: [.lexiAccent, .lexiAccentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Type scale

public extension Font {

    /// Lexi's display face — SF Serif. This is the brand voice: warm, literary,
    /// human, but set at a calm `.semibold` weight for a refined (not
    /// decorative) feel. Reserve it for the wordmark and large hero titles.
    static func lexiDisplay(_ size: CGFloat = 28, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
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

    /// Adds a *restrained* warm halo behind a view. Kept intentionally subtle
    /// (low radius/opacity) — reserve for the brand mark and the single key
    /// focal point on a surface, never for everyday chrome.
    func lexiGlow(radius: CGFloat = 10, opacity: Double = 0.18) -> some View {
        self.shadow(color: Color.lexiAccent.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}

// MARK: - Primary button style

/// Lexi's primary call-to-action button — a calm warm pill with a **solid**
/// accent fill (no gradient) and a gentle press spring. Use for the single
/// most important action on a surface (e.g. "Ask", "Start Buddy Capture",
/// "Get Started").
public struct LexiPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lexiHeadline)
            .foregroundStyle(.white)
            .padding(.horizontal, LexiTheme.Spacing.lg)
            .padding(.vertical, LexiTheme.Spacing.sm)
            .background(Color.lexiAccent, in: Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
