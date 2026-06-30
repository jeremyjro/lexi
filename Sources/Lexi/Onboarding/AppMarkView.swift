import SwiftUI

struct AppMarkView: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(OnboardingPalette.accentGradient)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.12), radius: size * 0.12, x: 0, y: size * 0.05)
    }
}

// BRAND: Replace this temporary glyph mark with the real branded app icon/wordmark.
