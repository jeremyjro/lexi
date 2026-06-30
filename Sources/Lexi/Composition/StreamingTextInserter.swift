import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class StreamingTextInserter {
    private var snapshot: StreamingPasteboardSnapshot?
    private var isActive = false
    private var finishRequested = false
    private var pendingText = ""
    private var pumpTask: Task<Void, Never>?

    func begin() {
        guard !isActive else { return }
        snapshot = StreamingPasteboardSnapshot(pasteboard: .general)
        isActive = true
        finishRequested = false
        pendingText = ""
    }

    func insert(_ text: String) {
        guard isActive, !text.isEmpty else { return }
        pendingText += text
        startPumpIfNeeded()
    }

    func finish() {
        guard isActive else { return }
        finishRequested = true
        startPumpIfNeeded()
    }

    func cancel() {
        guard isActive else { return }
        pendingText = ""
        finishRequested = true
        startPumpIfNeeded()
    }

    func replaceSelection(with text: String, allowKeyboardFallback: Bool) async -> Bool {
        if insertViaAccessibility(text, requireSelection: true) {
            return true
        }
        guard allowKeyboardFallback else { return false }
        let restoreSnapshot = text.isEmpty ? nil : StreamingPasteboardSnapshot(pasteboard: .general)
        if text.isEmpty {
            synthesizeDelete()
        } else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            try? await Task.sleep(nanoseconds: 45_000_000)
            synthesizePaste()
        }
        if let restoreSnapshot {
            try? await Task.sleep(nanoseconds: 650_000_000)
            restoreSnapshot.restore(to: .general)
        }
        return true
    }

    private func startPumpIfNeeded() {
        guard pumpTask == nil else { return }
        pumpTask = Task { @MainActor [weak self] in
            await self?.drainPendingText()
        }
    }

    private func drainPendingText() async {
        while isActive {
            let chunk = pendingText
            pendingText = ""
            guard !chunk.isEmpty else { break }
            await paste(chunk)
            try? await Task.sleep(nanoseconds: 140_000_000)
        }
        pumpTask = nil
        if finishRequested {
            restoreClipboardAfterPasteSettles()
        }
    }

    private func paste(_ text: String) async {
        if insertViaAccessibility(text, requireSelection: false) {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try? await Task.sleep(nanoseconds: 45_000_000)
        synthesizePaste()
    }

    private func restoreClipboardAfterPasteSettles() {
        isActive = false
        finishRequested = false
        pendingText = ""
        let restoreSnapshot = snapshot
        snapshot = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            restoreSnapshot?.restore(to: .general)
        }
    }

    private func insertViaAccessibility(_ text: String, requireSelection: Bool) -> Bool {
        guard let element = focusedTextElement(), !isPasswordField(element), isAttributeSettable(kAXValueAttribute, element) else {
            return false
        }
        let currentValue = stringAttribute(kAXValueAttribute, from: element) ?? ""
        let selectedRange = cfRangeAttribute(kAXSelectedTextRangeAttribute, from: element) ?? CFRange(location: currentValue.utf16.count, length: 0)
        guard (!requireSelection || selectedRange.length > 0),
              selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= currentValue.utf16.count else { return false }
        let nsRange = NSRange(location: selectedRange.location, length: selectedRange.length)
        guard let stringRange = Range(nsRange, in: currentValue) else { return false }
        let updatedValue = currentValue.replacingCharacters(in: stringRange, with: text)
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updatedValue as CFTypeRef) == .success else {
            return false
        }
        var newRange = CFRange(location: selectedRange.location + text.utf16.count, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
        return true
    }

    private func focusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value else { return nil }
        let element = value as! AXUIElement
        if isTextElement(element) {
            return element
        }
        return textDescendant(from: element, maxDepth: 4) ?? textAncestor(from: element)
    }

    private func textAncestor(from element: AXUIElement) -> AXUIElement? {
        var current = parentElement(of: element)
        for _ in 0..<6 {
            guard let candidate = current else { return nil }
            if isTextElement(candidate) {
                return candidate
            }
            current = parentElement(of: candidate)
        }
        return nil
    }

    private func textDescendant(from element: AXUIElement, maxDepth: Int) -> AXUIElement? {
        guard maxDepth >= 0 else { return nil }
        for child in children(of: element).prefix(40) {
            if isTextElement(child) {
                return child
            }
            if let match = textDescendant(from: child, maxDepth: maxDepth - 1) {
                return match
            }
        }
        return nil
    }

    private func isTextElement(_ element: AXUIElement) -> Bool {
        if isPasswordField(element) {
            return false
        }
        if isAttributeSettable(kAXValueAttribute, element) || cfRangeAttribute(kAXSelectedTextRangeAttribute, from: element) != nil {
            return true
        }
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, from: element) ?? ""
        return [role, subrole].contains { value in
            let normalized = value.lowercased()
            return normalized.contains("text") || normalized.contains("editor") || normalized.contains("input") || normalized.contains("textarea")
        }
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

    private func parentElement(of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard error == .success, let value else { return nil }
        return value as! AXUIElement?
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard error == .success, let children = value as? [AnyObject] else { return [] }
        return children.map { $0 as! AXUIElement }
    }

    private func isPasswordField(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, from: element) ?? ""
        let description = stringAttribute(kAXDescriptionAttribute, from: element) ?? ""
        return [role, subrole, description].contains { value in
            value.localizedCaseInsensitiveContains("password") || value.localizedCaseInsensitiveContains("secure")
        }
    }

    private func isAttributeSettable(_ attribute: String, _ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    private func synthesizePaste() {
        synthesizeKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }

    private func synthesizeDelete() {
        synthesizeKey(CGKeyCode(kVK_Delete), flags: [])
    }

    private func synthesizeKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        if let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            keyDown?.postToPid(processIdentifier)
            keyUp?.postToPid(processIdentifier)
        } else {
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}

private struct StreamingPasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { savedItem in
            let item = NSPasteboardItem()
            for (type, data) in savedItem {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
