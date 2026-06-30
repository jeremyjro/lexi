import AppKit
import Foundation
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    let markdown: String
    var bodySize: CGFloat = 15
    var onSelectionChanged: (String) -> Void = { _ in }
    var onDoubleClick: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> LexiMarkdownTextView {
        let textView = LexiMarkdownTextView()
        textView.delegate = context.coordinator
        textView.onDoubleClickSelection = onDoubleClick
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = CGSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.lexiAccentText
        ]
        textView.setMarkdown(markdown, bodySize: bodySize)
        return textView
    }

    func updateNSView(_ nsView: LexiMarkdownTextView, context: Context) {
        context.coordinator.parent = self
        nsView.delegate = context.coordinator
        nsView.onDoubleClickSelection = onDoubleClick
        nsView.linkTextAttributes = [
            .foregroundColor: NSColor.lexiAccentText
        ]
        nsView.setMarkdown(markdown, bodySize: bodySize)
        nsView.invalidateIntrinsicContentSize()
    }

    @available(macOS 13.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LexiMarkdownTextView, context: Context) -> CGSize? {
        let proposedWidth = proposal.width ?? nsView.textContainer?.containerSize.width ?? 0
        let width = proposedWidth > 0 ? proposedWidth : 356
        nsView.setTextContainerWidth(width)
        guard let textContainer = nsView.textContainer, let layoutManager = nsView.layoutManager else {
            return CGSize(width: width, height: 0)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: width, height: ceil(usedRect.height))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onSelectionChanged(textView.selectedText)
        }
    }
}

enum MarkdownBlockParser {
    enum Block {
        case heading(level: Int, text: String)
        case unorderedList(items: [String])
        case orderedList(items: [(marker: String, text: String)])
        case code(String)
        case blockquote(String)
        case paragraph(String)
    }

    static func blocks(from markdown: String) -> [Block] {
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
                if isFenceLine(line) {
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

            if isFenceLine(trimmed) {
                flushTextGroups()
                isInCodeBlock = true
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushTextGroups()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let item = parseUnorderedListItem(line) {
                flushParagraph()
                flushOrderedList()
                flushBlockquote()
                unorderedItems.append(item)
                continue
            }

            if let item = parseOrderedListItem(line) {
                flushParagraph()
                flushUnorderedList()
                flushBlockquote()
                orderedItems.append(item)
                continue
            }

            if let quote = parseBlockquoteLine(line) {
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
        var hashCount = 0
        for character in line {
            if character == "#" {
                hashCount += 1
            } else {
                break
            }
        }
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
        guard trimmed.first == ">" else { return nil }
        let afterMarker = trimmed.index(after: trimmed.startIndex)
        let textStart = (afterMarker < trimmed.endIndex && trimmed[afterMarker].isWhitespace)
            ? trimmed.index(after: afterMarker)
            : afterMarker
        let text = trimmed[textStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
}

enum MarkdownAttributedStringBuilder {
    static func attributedString(from markdown: String, bodySize: CGFloat) -> NSAttributedString {
        let blocks = MarkdownBlockParser.blocks(from: markdown)
        guard !blocks.isEmpty else {
            let placeholder = NSMutableAttributedString(string: "…")
            placeholder.addAttributes(
                [
                    .font: bodyFont(ofSize: bodySize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ],
                range: NSRange(location: 0, length: placeholder.length)
            )
            return placeholder
        }

        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            result.append(attributedString(for: block, bodySize: bodySize))
            if index < blocks.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private static func attributedString(for block: MarkdownBlockParser.Block, bodySize: CGFloat) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            return inlineAttributedString(
                raw: text,
                bodySize: bodySize,
                baseFont: headingFont(ofSize: bodySize, level: level),
                foregroundColor: .labelColor,
                defaultParagraphStyle: paragraphStyle(
                    lineSpacing: 2,
                    paragraphSpacingBefore: level == 1 ? 5 : 4,
                    paragraphSpacing: 6
                )
            )

        case .unorderedList(let items):
            return unorderedListAttributedString(items: items, bodySize: bodySize)

        case .orderedList(let items):
            return orderedListAttributedString(items: items, bodySize: bodySize)

        case .code(let code):
            let font = NSFont.monospacedSystemFont(ofSize: max(bodySize - 1, 11), weight: .regular)
            let attr = NSMutableAttributedString(string: code)
            attr.addAttributes(
                [
                    .font: font,
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.labelColor.withAlphaComponent(0.05),
                    .paragraphStyle: codeParagraphStyle()
                ],
                range: NSRange(location: 0, length: attr.length)
            )
            return attr

        case .blockquote(let text):
            return inlineAttributedString(
                raw: text,
                bodySize: bodySize,
                baseFont: bodyFont(ofSize: bodySize),
                foregroundColor: .secondaryLabelColor,
                defaultParagraphStyle: blockquoteParagraphStyle()
            )

        case .paragraph(let text):
            return inlineAttributedString(
                raw: text,
                bodySize: bodySize,
                baseFont: bodyFont(ofSize: bodySize),
                foregroundColor: .labelColor,
                defaultParagraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 6)
            )
        }
    }

    private static func unorderedListAttributedString(items: [String], bodySize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            let raw = "•\t" + item
            let attr = inlineAttributedString(
                raw: raw,
                bodySize: bodySize,
                baseFont: bodyFont(ofSize: bodySize),
                foregroundColor: .labelColor,
                defaultParagraphStyle: listParagraphStyle()
            )
            result.append(attr)
            if index < items.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private static func orderedListAttributedString(items: [(marker: String, text: String)], bodySize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            let raw = "\(item.marker)\t" + item.text
            let attr = inlineAttributedString(
                raw: raw,
                bodySize: bodySize,
                baseFont: bodyFont(ofSize: bodySize),
                foregroundColor: .labelColor,
                defaultParagraphStyle: listParagraphStyle()
            )
            result.append(attr)
            if index < items.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private static func inlineAttributedString(
        raw: String,
        bodySize: CGFloat,
        baseFont: NSFont,
        foregroundColor: NSColor,
        defaultParagraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        guard let parsed = try? AttributedString(markdown: raw, options: options) else {
            let fallback = NSMutableAttributedString(string: raw)
            fallback.addAttributes(
                [
                    .font: baseFont,
                    .foregroundColor: foregroundColor,
                    .paragraphStyle: defaultParagraphStyle
                ],
                range: NSRange(location: 0, length: fallback.length)
            )
            return fallback
        }

        let output = NSMutableAttributedString(string: String(parsed.characters))
        output.addAttributes(
            [
                .font: baseFont,
                .foregroundColor: foregroundColor,
                .paragraphStyle: defaultParagraphStyle
            ],
            range: NSRange(location: 0, length: output.length)
        )

        for run in parsed.runs {
            let range = NSRange(run.range, in: parsed)
            guard range.length > 0 else { continue }
            let intent = run.inlinePresentationIntent

            if intent?.contains(.code) == true {
                output.addAttributes(
                    [
                        .font: NSFont.monospacedSystemFont(ofSize: bodySize, weight: .regular),
                        .backgroundColor: NSColor.labelColor.withAlphaComponent(0.07)
                    ],
                    range: range
                )
            } else {
                var font = baseFont
                var traits = NSFontDescriptor.SymbolicTraits()
                if intent?.contains(.stronglyEmphasized) == true {
                    traits.insert(.bold)
                }
                if intent?.contains(.emphasized) == true {
                    traits.insert(.italic)
                }
                if !traits.isEmpty {
                    font = font.applying(symbolicTraits: traits)
                }
                output.addAttribute(.font, value: font, range: range)
                output.addAttribute(.foregroundColor, value: foregroundColor, range: range)
            }

            if let url = run.link {
                output.addAttribute(.link, value: url, range: range)
            }
        }

        return output
    }

    private static func headingFont(ofSize bodySize: CGFloat, level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = min(bodySize + 4, 22)
        case 2: size = min(bodySize + 3, 20)
        case 3: size = min(bodySize + 2, 19)
        case 4: size = min(bodySize + 1, 18)
        case 5: size = min(bodySize, 17)
        default: size = min(bodySize, 16)
        }
        return bodyFont(ofSize: size, weight: .semibold)
    }

    private static func bodyFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let font = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return font
    }

    private static func paragraphStyle(
        lineSpacing: CGFloat,
        paragraphSpacingBefore: CGFloat = 0,
        paragraphSpacing: CGFloat = 0,
        headIndent: CGFloat = 0,
        firstLineHeadIndent: CGFloat = 0,
        tabLocation: CGFloat? = nil
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = paragraphSpacingBefore
        style.paragraphSpacing = paragraphSpacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineHeadIndent
        style.lineBreakMode = .byWordWrapping
        if let tabLocation {
            style.tabStops = [NSTextTab(textAlignment: .left, location: tabLocation, options: [:])]
            style.defaultTabInterval = tabLocation
        }
        return style.copy() as? NSParagraphStyle ?? style
    }

    private static func listParagraphStyle() -> NSParagraphStyle {
        paragraphStyle(
            lineSpacing: 4,
            paragraphSpacing: 2,
            headIndent: 20,
            firstLineHeadIndent: 0,
            tabLocation: 20
        )
    }

    private static func blockquoteParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 5
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.lineBreakMode = .byWordWrapping
        return style.copy() as? NSParagraphStyle ?? style
    }

    private static func codeParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 6
        style.lineBreakMode = .byWordWrapping
        return style.copy() as? NSParagraphStyle ?? style
    }
}

final class LexiMarkdownTextView: NSTextView {
    var onDoubleClickSelection: ((String) -> Void)?
    var renderedMarkdown: String = ""
    var renderedBodySize: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount >= 2 else { return }
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onDoubleClickSelection?(text)
    }

    func setMarkdown(_ markdown: String, bodySize: CGFloat) {
        guard markdown != renderedMarkdown || bodySize != renderedBodySize else { return }
        renderedMarkdown = markdown
        renderedBodySize = bodySize
        let attributed = MarkdownAttributedStringBuilder.attributedString(from: markdown, bodySize: bodySize)
        textStorage?.setAttributedString(attributed)
        invalidateIntrinsicContentSize()
    }

    func setTextContainerWidth(_ width: CGFloat) {
        guard let textContainer else { return }
        textContainer.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let width = textContainer.containerSize.width
        guard width > 0 else { return super.intrinsicContentSize }
        return NSSize(width: width, height: ceil(usedRect.height))
    }
}

private extension NSFont {
    func applying(symbolicTraits traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
