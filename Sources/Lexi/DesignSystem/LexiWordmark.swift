import SwiftUI
import AppKit

/// The Lexi brand mark glyph — a friendly rounded "L" with a detached *spark*
/// dot at the upper-right (the moment of understanding).
///
/// `LexiMark` is a pure `Shape`, so it scales crisply at any size and can be
/// filled with a solid color, the Aurora gradient, or used as a mask. Its
/// geometry intentionally matches the app icon so the mark reads consistently
/// from a 16pt menu-bar item up to a 1024pt icon.
public struct LexiMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let corner = 0.05 * w

        // Vertical stem of the "L".
        let stem = CGRect(
            x: rect.minX + 0.30 * w,
            y: rect.minY + 0.16 * h,
            width: 0.17 * w,
            height: 0.68 * h
        )
        path.addRoundedRect(in: stem, cornerSize: CGSize(width: corner, height: corner), style: .continuous)

        // Horizontal foot of the "L".
        let foot = CGRect(
            x: rect.minX + 0.30 * w,
            y: rect.minY + 0.67 * h,
            width: 0.44 * w,
            height: 0.17 * h
        )
        path.addRoundedRect(in: foot, cornerSize: CGSize(width: corner, height: corner), style: .continuous)

        // The detached "spark" dot.
        let dotRadius = 0.085 * w
        let dot = CGRect(
            x: rect.minX + 0.70 * w - dotRadius,
            y: rect.minY + 0.26 * h - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        path.addEllipse(in: dot)

        return path
    }
}

/// The Lexi app-icon-style badge: a rounded "squircle" filled with the Aurora
/// gradient, the white ``LexiMark`` centered on it, and a soft warm glow.
///
/// Use this in headers and anywhere the full brand icon should appear (Settings
/// header, onboarding welcome, About). For a flat single-color glyph use
/// ``LexiMonogram`` instead.
public struct LexiBrandMark: View {
    private let size: CGFloat
    private let glow: Bool

    /// - Parameters:
    ///   - size: The square edge length in points.
    ///   - glow: Whether to render a subtle warm halo behind the badge. Off by
    ///     default to keep surfaces calm; enable only for a hero focal point.
    public init(size: CGFloat = 44, glow: Bool = false) {
        self.size = size
        self.glow = glow
    }

    public var body: some View {
        let corner = size * 0.225
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient.lexiWarm)
            .overlay(
                LexiMark()
                    .fill(.white)
                    .padding(size * 0.04)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: max(0.5, size * 0.01))
            )
            .frame(width: size, height: size)
            .modifier(ConditionalGlow(enabled: glow, radius: size * 0.22))
            .accessibilityLabel("Lexi")
    }
}

private struct ConditionalGlow: ViewModifier {
    let enabled: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.lexiGlow(radius: radius, opacity: 0.18)
        } else {
            content
        }
    }
}

/// A flat single-color Lexi monogram (the ``LexiMark`` glyph) for compact or
/// tinted contexts such as the menu-bar item, inline labels and watermarks.
public struct LexiMonogram: View {
    private let size: CGFloat
    private let color: Color

    public init(size: CGFloat = 18, color: Color = .lexiInk) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        LexiMark()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityLabel("Lexi")
    }
}

/// The Lexi wordmark — "Lexi" set in the brand serif face at a calm, refined
/// weight. No decorative flourishes; the warmth comes from the serif itself.
/// Optionally pairs with the brand-mark badge for a full lockup, where the
/// badge carries the single accent touch.
///
/// Use the wordmark in product headers (Settings, onboarding) and the About
/// surface. Keep it on a calm paper background; never place it over busy
/// imagery.
public struct LexiWordmark: View {
    /// How the wordmark is laid out.
    public enum Layout {
        /// Just the "Lexi" serif wordmark.
        case wordmarkOnly
        /// The brand-mark badge followed by the "Lexi" wordmark.
        case badgeAndWordmark
    }

    private let size: CGFloat
    private let layout: Layout

    /// - Parameters:
    ///   - size: The cap height of the wordmark in points (the badge is scaled
    ///     to match).
    ///   - layout: Whether to show the leading brand-mark badge.
    public init(size: CGFloat = 28, layout: Layout = .wordmarkOnly) {
        self.size = size
        self.layout = layout
    }

    public var body: some View {
        HStack(spacing: size * 0.46) {
            if layout == .badgeAndWordmark {
                LexiBrandMark(size: size * 1.5, glow: false)
            }
            wordmark
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lexi")
    }

    private var wordmark: some View {
        Text("Lexi")
            .font(.lexiDisplay(size))
            .foregroundStyle(Color.lexiInk)
            .fixedSize()
    }
}

// MARK: - AppKit bridges

/// AppKit-facing helpers for surfaces that aren't SwiftUI — chiefly the
/// menu-bar status item.
public enum LexiBrand {

    /// A template `NSImage` of the Lexi monogram, suitable for an
    /// `NSStatusItem` button. Because it is a template image, macOS tints it
    /// automatically for light/dark menu bars and selection.
    ///
    /// Adopt in `AppDelegate` by replacing the `textformat` symbol:
    /// ```swift
    /// item.button?.image = LexiBrand.statusItemImage()
    /// ```
    public static func statusItemImage(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let w = rect.width
            let h = rect.height
            let corner = 0.05 * w

            let stem = CGRect(x: rect.minX + 0.30 * w, y: rect.minY + 0.16 * h, width: 0.17 * w, height: 0.68 * h)
            let foot = CGRect(x: rect.minX + 0.30 * w, y: rect.minY + 0.67 * h, width: 0.44 * w, height: 0.17 * h)
            let dotRadius = 0.085 * w
            let dot = CGRect(
                x: rect.minX + 0.70 * w - dotRadius,
                y: rect.minY + 0.26 * h - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )

            context.setFillColor(NSColor.black.cgColor)
            context.addPath(CGPath(roundedRect: stem, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.addPath(CGPath(roundedRect: foot, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.addPath(CGPath(ellipseIn: dot, transform: nil))
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
