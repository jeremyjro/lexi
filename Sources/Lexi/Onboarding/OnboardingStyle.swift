import SwiftUI

enum OnboardingPalette {
    // BRAND: Swap this accent gradient and the temporary app mark for the brand session tokens.
    static let accentStart = Color(red: 1.0, green: 0.45, blue: 0.32)
    static let accentEnd = Color(red: 1.0, green: 0.66, blue: 0.30)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentStart, accentEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func background(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color(red: 0.99, green: 0.95, blue: 0.91)
        case .dark:
            return Color(red: 0.15, green: 0.12, blue: 0.10)
        @unknown default:
            return Color(red: 0.99, green: 0.95, blue: 0.91)
        }
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.white.opacity(0.72)
        case .dark:
            return Color(red: 0.22, green: 0.18, blue: 0.15)
        @unknown default:
            return Color.white.opacity(0.72)
        }
    }

    static func mutedSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.04)
        case .dark:
            return Color.white.opacity(0.08)
        @unknown default:
            return Color.black.opacity(0.04)
        }
    }

    static func subtleStroke(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.08)
        case .dark:
            return Color.white.opacity(0.10)
        @unknown default:
            return Color.black.opacity(0.08)
        }
    }
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
