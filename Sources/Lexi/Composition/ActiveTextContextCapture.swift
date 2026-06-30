import AppKit
import ApplicationServices

struct ActiveTextCompositionContext {
    let appName: String
    let windowTitle: String
    let selectedText: String
    let surroundingText: String
    let currentText: String
    let isWritable: Bool
}

final class ActiveTextContextCapture {
    private let maxCurrentTextLength = 2400
    private let contextRadius = 900

    func capture(selectedText overrideSelectedText: String? = nil, surroundingText overrideSurroundingText: String? = nil) -> ActiveTextCompositionContext? {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windowTitle = focusedWindow(from: appElement).flatMap { stringAttribute(kAXTitleAttribute, from: $0) } ?? ""
        guard let focusedElement = focusedElement() else {
            return ActiveTextCompositionContext(
                appName: appName,
                windowTitle: windowTitle,
                selectedText: overrideSelectedText ?? "",
                surroundingText: overrideSurroundingText ?? "",
                currentText: "",
                isWritable: isTrustedEditorHost(appName: appName)
            )
        }
        let writableElement = preferredWritableElement(startingAt: focusedElement)
        let targetElement = writableElement ?? focusedElement

        let selectedRange = cfRangeAttribute(kAXSelectedTextRangeAttribute, from: targetElement)
        let fullValue = stringAttribute(kAXValueAttribute, from: targetElement) ?? ""
        let selectedText = overrideSelectedText
            ?? stringAttribute(kAXSelectedTextAttribute, from: targetElement)
            ?? selectedRange.flatMap { selectedTextFromRange($0, in: fullValue) }
            ?? ""
        let surroundingText = overrideSurroundingText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? overrideSurroundingText ?? ""
            : surroundingPassage(in: fullValue, selectedRange: selectedRange)
        let currentText = String(fullValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCurrentTextLength))

        let writable = writableElement != nil || isTrustedEditorHost(appName: appName)
        if !writable {
            let role = stringAttribute(kAXRoleAttribute, from: focusedElement) ?? "unknown"
            let subrole = stringAttribute(kAXSubroleAttribute, from: focusedElement) ?? "unknown"
            print("Lexi composition target rejected: app='\(appName)' window='\(windowTitle)' role='\(role)' subrole='\(subrole)'")
        }

        return ActiveTextCompositionContext(
            appName: appName,
            windowTitle: windowTitle,
            selectedText: selectedText,
            surroundingText: surroundingText,
            currentText: currentText,
            isWritable: writable
        )
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

    private func booleanAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? Bool
    }

    private func parentElement(of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard error == .success, let value else { return nil }
        return value as! AXUIElement?
    }

    private func preferredWritableElement(startingAt element: AXUIElement) -> AXUIElement? {
        if let descendant = writableDescendantWithText(from: element, maxDepth: 4) {
            return descendant
        }
        return writableElement(startingAt: element)
    }

    private func writableElement(startingAt element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let candidate = current else { return nil }
            if isWritableTextElement(candidate) {
                return candidate
            }
            current = parentElement(of: candidate)
        }
        return nil
    }

    private func writableDescendantWithText(from element: AXUIElement, maxDepth: Int) -> AXUIElement? {
        guard maxDepth >= 0 else { return nil }
        if isWritableTextElement(element), stringAttribute(kAXValueAttribute, from: element)?.isEmpty == false {
            return element
        }
        for child in children(of: element).prefix(40) {
            if let match = writableDescendantWithText(from: child, maxDepth: maxDepth - 1) {
                return match
            }
        }
        return nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard error == .success, let children = value as? [AnyObject] else { return [] }
        return children.map { $0 as! AXUIElement }
    }

    private func selectedTextFromRange(_ range: CFRange, in text: String) -> String? {
        guard range.location >= 0, range.length > 0 else { return nil }
        let nsRange = NSRange(location: range.location, length: range.length)
        guard let stringRange = Range(nsRange, in: text) else { return nil }
        return String(text[stringRange])
    }

    private func surroundingPassage(in text: String, selectedRange: CFRange?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let selectedRange, selectedRange.location >= 0 else {
            return String(trimmed.prefix(maxCurrentTextLength))
        }

        let start = max(0, selectedRange.location - contextRadius)
        let end = min(text.utf16.count, selectedRange.location + selectedRange.length + contextRadius)
        let nsRange = NSRange(location: start, length: max(0, end - start))
        guard let range = Range(nsRange, in: text) else {
            return String(trimmed.prefix(maxCurrentTextLength))
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isWritableTextElement(_ element: AXUIElement) -> Bool {
        if isPasswordField(element) || booleanAttribute(kAXEnabledAttribute, from: element) == false {
            return false
        }
        if booleanAttribute("AXEditable", from: element) == true {
            return true
        }
        if isAttributeSettable(kAXValueAttribute, element) || isAttributeSettable(kAXSelectedTextAttribute, element) {
            return true
        }
        if cfRangeAttribute(kAXSelectedTextRangeAttribute, from: element) != nil {
            return true
        }
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, from: element) ?? ""
        let title = stringAttribute(kAXTitleAttribute, from: element) ?? ""
        let description = stringAttribute(kAXDescriptionAttribute, from: element) ?? ""
        let help = stringAttribute(kAXHelpAttribute, from: element) ?? ""
        return [role, subrole, title, description, help].contains { value in
            let normalized = value.lowercased()
            return normalized.contains("text")
                || normalized.contains("editor")
                || normalized.contains("input")
                || normalized.contains("textarea")
                || normalized.contains("compose")
                || normalized.contains("message")
                || normalized.contains("comment")
                || normalized.contains("reply")
                || normalized.contains("search")
                || normalized.contains("note")
        }
    }

    private func isPasswordField(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, from: element) ?? ""
        let description = stringAttribute(kAXDescriptionAttribute, from: element) ?? ""
        return [role, subrole, description].contains { value in
            value.localizedCaseInsensitiveContains("password") || value.localizedCaseInsensitiveContains("secure")
        }
    }

    private func isTrustedEditorHost(appName: String) -> Bool {
        let normalized = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trustedEditorApps: Set<String> = [
            // AI apps
            "claude",
            // Browsers (web textareas respond to Cmd+V even if AX doesn't expose settable attrs)
            "google chrome",
            "chrome",
            "arc",
            "safari",
            "firefox",
            "brave browser",
            "microsoft edge",
            "opera",
            "chromium",
            "vivaldi",
            // Editors and productivity
            "obsidian",
            "notion",
            "slack",
            "textedit",
            "notes",
            "bear",
            "ulysses",
            "ia writer",
            "visual studio code",
            "cursor"
        ]
        return trustedEditorApps.contains(normalized)
    }

    private func isAttributeSettable(_ attribute: String, _ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }
}
