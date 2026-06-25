import AppKit
import ApplicationServices

struct CapturedSelection {
    enum Source {
        case accessibility
        case clipboardFallback
    }

    let term: String
    let passage: String
    let windowTitle: String
    let appName: String
    let anchorRect: CGRect?
    let source: Source
    let question: String?

    func withQuestion(_ question: String) -> CapturedSelection {
        CapturedSelection(
            term: term,
            passage: passage,
            windowTitle: windowTitle,
            appName: appName,
            anchorRect: anchorRect,
            source: source,
            question: question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : question.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

enum SelectionCaptureStatus {
    case success(CapturedSelection)
    case noSelection(appName: String, windowTitle: String)
    case accessibilityPermissionMissing
}

final class SelectionCapture {
    private let clipboardFallback = ClipboardFallback()
    private let maxPassageLength = 600
    private let contextRadius = 300
    private let maxAXNodesToVisit = 250

    func capture() -> SelectionCaptureStatus {
        guard AXIsProcessTrusted() else {
            return .accessibilityPermissionMissing
        }

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let appElement: AXUIElement? = NSWorkspace.shared.frontmostApplication.map { AXUIElementCreateApplication($0.processIdentifier) }
        let currentFocusedWindow: AXUIElement? = appElement.flatMap { focusedWindow(from: $0) }
        let windowTitle = currentFocusedWindow.flatMap { stringAttribute(kAXTitleAttribute, from: $0) } ?? ""

        guard let focusedElement = focusedElement() else {
            return clipboardCapture(appName: appName, windowTitle: windowTitle)
        }

        let selectedText = stringAttribute(kAXSelectedTextAttribute, from: focusedElement)
        let selectedRange = cfRangeAttribute(kAXSelectedTextRangeAttribute, from: focusedElement)
        let fullValue = stringAttribute(kAXValueAttribute, from: focusedElement) ?? ""
        let rangeText = selectedRange.flatMap { selectedTextFromRange($0, in: fullValue) }
        let term = normalized(selectedText ?? rangeText ?? "")

        guard !term.isEmpty else {
            return clipboardCapture(appName: appName, windowTitle: windowTitle)
        }

        let passage = bestPassage(
            term: term,
            focusedElement: focusedElement,
            focusedWindow: currentFocusedWindow,
            fullValue: fullValue,
            selectedRange: selectedRange
        )
        let anchorRect = selectedRange.flatMap { boundsForRange($0, in: focusedElement) }

        return .success(CapturedSelection(
            term: term,
            passage: passage,
            windowTitle: windowTitle,
            appName: appName,
            anchorRect: anchorRect,
            source: .accessibility,
            question: nil
        ))
    }

    private func bestPassage(
        term: String,
        focusedElement: AXUIElement,
        focusedWindow: AXUIElement?,
        fullValue: String,
        selectedRange: CFRange?
    ) -> String {
        if let selectedRange {
            let directPassage = surroundingPassage(in: fullValue, selectedRange: selectedRange)
            if !directPassage.isEmpty {
                return directPassage
            }

            let rangePassage = stringForExpandedRange(around: selectedRange, in: focusedElement)
            if !rangePassage.isEmpty {
                return rangePassage
            }
        }

        if let focusedElementText = collectedText(from: focusedElement, selectedTerm: term), !focusedElementText.isEmpty {
            return contextAround(term: term, in: focusedElementText)
        }

        if let focusedWindow,
           let focusedWindowText = collectedText(from: focusedWindow, selectedTerm: term),
           !focusedWindowText.isEmpty {
            return contextAround(term: term, in: focusedWindowText)
        }

        if !fullValue.isEmpty {
            return contextAround(term: term, in: fullValue)
        }

        return ""
    }

    private func clipboardCapture(appName: String, windowTitle: String) -> SelectionCaptureStatus {
        let term = normalized(clipboardFallback.copyCurrentSelection())
        guard !term.isEmpty else {
            return .noSelection(appName: appName, windowTitle: windowTitle)
        }

        return .success(CapturedSelection(
            term: term,
            passage: "",
            windowTitle: windowTitle,
            appName: appName,
            anchorRect: nil,
            source: .clipboardFallback,
            question: nil
        ))
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        guard error == .success, let value else { return nil }
        return value as! AXUIElement?
    }

    private func focusedWindow(from appElement: AXUIElement) -> AXUIElement? {
        var focusedWindow: AnyObject?
        let error = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard error == .success, let focusedWindow else { return nil }
        return focusedWindow as! AXUIElement?
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? String
    }

    private func cfRangeAttribute(_ attribute: String, from element: AXUIElement) -> CFRange? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return nil }

        let axValue = value as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private func selectedTextFromRange(_ range: CFRange, in text: String) -> String? {
        guard range.location >= 0, range.length > 0 else { return nil }
        let nsRange = NSRange(location: range.location, length: range.length)
        guard let stringRange = Range(nsRange, in: text) else { return nil }
        return String(text[stringRange])
    }

    private func surroundingPassage(in text: String, selectedRange: CFRange) -> String {
        guard !text.isEmpty, selectedRange.location >= 0 else { return "" }
        let nsRange = NSRange(location: selectedRange.location, length: selectedRange.length)
        guard let stringRange = Range(nsRange, in: text) else {
            return normalized(String(text.prefix(maxPassageLength)))
        }

        let beforeStart = text.index(stringRange.lowerBound, offsetBy: -contextRadius, limitedBy: text.startIndex) ?? text.startIndex
        let afterEnd = text.index(stringRange.upperBound, offsetBy: contextRadius, limitedBy: text.endIndex) ?? text.endIndex
        return normalized(String(text[beforeStart..<afterEnd]))
    }

    private func stringForExpandedRange(around selectedRange: CFRange, in element: AXUIElement) -> String {
        guard selectedRange.location >= 0 else { return "" }

        var expandedRange = CFRange(
            location: max(0, selectedRange.location - contextRadius),
            length: selectedRange.length + contextRadius * 2
        )
        guard let rangeValue = AXValueCreate(.cfRange, &expandedRange) else { return "" }

        var value: AnyObject?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard error == .success, let text = value as? String else { return "" }
        return normalized(String(text.prefix(maxPassageLength)))
    }

    private func collectedText(from root: AXUIElement, selectedTerm: String) -> String? {
        var visited = 0
        var snippets: [String] = []
        collectText(from: root, snippets: &snippets, visited: &visited)

        let joined = normalized(snippets.joined(separator: " "))
        guard !joined.isEmpty else { return nil }
        return joined
    }

    private func collectText(from element: AXUIElement, snippets: inout [String], visited: inout Int) {
        guard visited < maxAXNodesToVisit else { return }
        visited += 1

        for attribute in [kAXSelectedTextAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
            if let text = stringAttribute(attribute, from: element) {
                let cleaned = normalized(text)
                if cleaned.count > 1 {
                    snippets.append(cleaned)
                }
            }
        }

        for attribute in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, kAXRowsAttribute, kAXColumnsAttribute] {
            for child in elementArrayAttribute(attribute, from: element) {
                collectText(from: child, snippets: &snippets, visited: &visited)
            }
        }
    }

    private func elementArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return [] }

        if let elements = value as? [AXUIElement] {
            return elements
        }

        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [value as! AXUIElement]
        }

        return []
    }

    private func contextAround(term: String, in text: String) -> String {
        let normalizedText = normalized(text)
        guard !normalizedText.isEmpty else { return "" }

        if let range = normalizedText.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            let beforeStart = normalizedText.index(range.lowerBound, offsetBy: -contextRadius, limitedBy: normalizedText.startIndex) ?? normalizedText.startIndex
            let afterEnd = normalizedText.index(range.upperBound, offsetBy: contextRadius, limitedBy: normalizedText.endIndex) ?? normalizedText.endIndex
            return normalized(String(normalizedText[beforeStart..<afterEnd]))
        }

        return normalized(String(normalizedText.prefix(maxPassageLength)))
    }

    private func boundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var boundsValue: AnyObject?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )
        guard error == .success, let boundsValue else { return nil }

        let axValue = boundsValue as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private func normalized(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
