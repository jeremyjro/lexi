import SwiftUI

enum OnboardingPalette {
    /// The single warm brand accent. The gradient is reserved for brand-mark
    /// moments; in chrome prefer the solid `accentStart`.
    static let accentStart = Color.lexiAccent
    static let accentEnd = Color.lexiAccentDeep

    static var accentGradient: LinearGradient { .lexiWarm }

    // Onboarding rides on the shared warm-paper tokens, which already resolve
    // light/dark, so these ignore the passed scheme and return the dynamic token.
    static func background(for colorScheme: ColorScheme) -> Color { .lexiPaper }

    static func surface(for colorScheme: ColorScheme) -> Color { .lexiPaperElevated }

    static func mutedSurface(for colorScheme: ColorScheme) -> Color { .lexiPaperSunken }

    static func subtleStroke(for colorScheme: ColorScheme) -> Color { .lexiHairline }
}

enum OnboardingTypography {
    static func display(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }

    static func strongBody(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

enum OnboardingMetrics {
    static let cornerRadius: CGFloat = 28
    static let cardCornerRadius: CGFloat = 22
    static let smallCornerRadius: CGFloat = 16
}
