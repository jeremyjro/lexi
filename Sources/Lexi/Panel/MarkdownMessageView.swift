import Foundation
import SwiftUI

struct MarkdownMessageView: View {
    let markdown: String
    var bodySize: CGFloat = 15

    var body: some View {
        let blocks = Self.parseBlocks(from: markdown)
        Group {
            if blocks.isEmpty {
                Text("…")
                    .font(.system(size: bodySize, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
            }
        }
    }

    private enum Block {
        case heading(level: Int, text: String)
        case unorderedList(items: [String])
        case orderedList(items: [(marker: String, text: String)])
        case code(String)
        case blockquote(String)
        case paragraph(String)
    }

    private static func parseBlocks(from markdown: String) -> [Block] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [(marker: String, text: String)] = []
        var blockquoteLines: [String] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            blocks.append(.unorderedList(items: unorderedItems))
            unorderedItems.removeAll(keepingCapacity: true)
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            blocks.append(.orderedList(items: orderedItems))
            orderedItems.removeAll(keepingCapacity: true)
        }

        func flushBlockquote() {
            guard !blockquoteLines.isEmpty else { return }
            blocks.append(.blockquote(blockquoteLines.joined(separator: " ")))
            blockquoteLines.removeAll(keepingCapacity: true)
        }

        func flushCodeBlock() {
            guard !codeLines.isEmpty else { return }
            blocks.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll(keepingCapacity: true)
        }

        func flushTextGroups() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
            flushBlockquote()
        }

        for line in lines {
            if isInCodeBlock {
                if Self.isFenceLine(line) {
                    flushCodeBlock()
                    isInCodeBlock = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushTextGroups()
                continue
            }

            if Self.isFenceLine(trimmed) {
                flushTextGroups()
                isInCodeBlock = true
                continue
            }

            if let heading = Self.parseHeading(trimmed) {
                flushTextGroups()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let item = Self.parseUnorderedListItem(line) {
                flushParagraph()
                flushOrderedList()
                flushBlockquote()
                unorderedItems.append(item)
                continue
            }

            if let item = Self.parseOrderedListItem(line) {
                flushParagraph()
                flushUnorderedList()
                flushBlockquote()
                orderedItems.append(item)
                continue
            }

            if let quote = Self.parseBlockquoteLine(line) {
                flushParagraph()
                flushUnorderedList()
                flushOrderedList()
                blockquoteLines.append(quote)
                continue
            }

            flushUnorderedList()
            flushOrderedList()
            flushBlockquote()
            paragraphLines.append(trimmed)
        }

        if isInCodeBlock {
            flushCodeBlock()
        }
        flushTextGroups()
        return blocks
    }

    private static func isFenceLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashCount) else { return nil }
        let remainder = line.dropFirst(hashCount)
        guard remainder.first?.isWhitespace == true else { return nil }
        let text = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (level: hashCount, text: text)
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }
        guard let marker = trimmed.first, "-*+".contains(marker) else { return nil }
        let afterMarker = trimmed.index(after: trimmed.startIndex)
        guard afterMarker < trimmed.endIndex, trimmed[afterMarker].isWhitespace else { return nil }
        let textStart = trimmed.index(after: afterMarker)
        let text = trimmed[textStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func parseOrderedListItem(_ line: String) -> (marker: String, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index].isNumber {
            index = trimmed.index(after: index)
        }
        guard index > trimmed.startIndex else { return nil }
        guard index < trimmed.endIndex, (trimmed[index] == "." || trimmed[index] == ")") else { return nil }
        let markerIndex = trimmed.index(after: index)
        guard markerIndex < trimmed.endIndex, trimmed[markerIndex].isWhitespace else { return nil }
        let textStart = trimmed.index(after: markerIndex)
        let text = trimmed[textStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let number = String(trimmed[..<index])
        return (marker: number + ".", text: text)
    }

    private static func parseBlockquoteLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == ">" else { return nil }
        let afterMarker = trimmed.index(after: trimmed.startIndex)
        let textStart = (afterMarker < trimmed.endIndex && trimmed[afterMarker].isWhitespace)
            ? trimmed.index(after: afterMarker)
            : afterMarker
        let text = trimmed[textStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(.system(size: headingSize(for: level), weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: bodySize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        inlineText(item)
                            .font(.system(size: bodySize, weight: .regular, design: .rounded))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: item.marker)
                            .font(.system(size: bodySize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        inlineText(item.text)
                            .font(.system(size: bodySize, weight: .regular, design: .rounded))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                }
            }
        case .code(let code):
            Text(verbatim: code)
                .font(.system(size: max(bodySize - 1, 11), weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                // BRAND: accent bar color
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                inlineText(text)
                    .font(.system(size: bodySize, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: bodySize, weight: .regular, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return min(bodySize + 4, 22)
        case 2: return min(bodySize + 3, 20)
        case 3: return min(bodySize + 2, 19)
        case 4: return min(bodySize + 1, 18)
        case 5: return min(bodySize, 17)
        default: return min(bodySize, 16)
        }
    }

    private func inlineText(_ raw: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var attr = (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
        let runs = Array(attr.runs)
        for run in runs where run.inlinePresentationIntent?.contains(.code) == true {
            attr[run.range].font = .system(size: bodySize, weight: .regular, design: .monospaced)
            attr[run.range].backgroundColor = Color.primary.opacity(0.07)
            // BRAND: link/accent color
        }
        return Text(attr)
    }
}
