import AppKit
import SwiftUI

struct BuddyCalloutParseResult {
    let answer: String
    let point: CGPoint?
    let label: String?
}

enum BuddyCalloutParser {
    static func parse(_ text: String) -> BuddyCalloutParseResult {
        let pattern = #"\[CALLOUT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]]+))?)\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let tagRange = Range(match.range, in: text) else {
            return BuddyCalloutParseResult(answer: text, point: nil, label: nil)
        }

        let answer = String(text[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard match.numberOfRanges >= 3,
              let xRange = Range(match.range(at: 1), in: text),
              let yRange = Range(match.range(at: 2), in: text),
              let x = Double(text[xRange]),
              let y = Double(text[yRange]) else {
            return BuddyCalloutParseResult(answer: answer, point: nil, label: nil)
        }

        let label: String?
        if match.numberOfRanges >= 4, let labelRange = Range(match.range(at: 3), in: text) {
            label = String(text[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            label = nil
        }
        return BuddyCalloutParseResult(answer: answer, point: CGPoint(x: x, y: y), label: label)
    }
}

@MainActor
final class BuddyCalloutOverlayController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(point: CGPoint, label: String?) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let size = NSSize(width: 180, height: 58)
        let origin = NSPoint(x: point.x - 16, y: point.y + 8)
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: BuddyCalloutView(label: label ?? "Here"))
        panel.orderFrontRegardless()
        self.panel = panel

        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            self.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct BuddyCalloutView: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.blue)
                .frame(width: 14, height: 14)
                .shadow(color: .blue.opacity(0.8), radius: 8)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.35), lineWidth: 1)
        )
    }
}
