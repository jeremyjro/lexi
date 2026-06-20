import Cocoa
import ApplicationServices

class AccessibilityManager {
    private var isTracking = false
    private var trackedElement: AXUIElement?
    private var fullDocumentText: String = ""
    private var currentApp: String = ""
    private var lastTextCaptureTime: Date = Date()
    private let screenCaptureManager = ScreenCaptureManager()
    
    func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("Accessibility permissions: \(accessEnabled)")
    }
    
    func startTracking() {
        isTracking = true
        if let element = getCurrentFocusedElement() {
            trackedElement = element
            // Capture full document text when tracking starts
            captureFullDocumentText()
        }
    }
    
    func stopTrackingAndGetSelection() -> String? {
        isTracking = false
        let selectedText = getSelectedText()
        print("Selected text: \(selectedText ?? "nil")")
        return selectedText
    }
    
    func getSurroundingContext(for term: String) -> String {
        let separator = String(repeating: "=", count: 60)
        print("\n" + separator)
        print("STEP 2: GETTING SURROUNDING CONTEXT")
        print(separator)
        print("Term: '\(term)'")
        print("Document text length: \(fullDocumentText.count) characters")
        
        let context = extractContext(for: term, from: fullDocumentText)
        
        print("✅ STEP 2: Context extracted: \(context.count) characters")
        print("✅ Context preview: \(String(context.prefix(200)))...")
        print(separator + "\n")
        
        return context
    }
    
    func getCurrentAppName() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        currentApp = app?.localizedName ?? "Unknown"
        return currentApp
    }
    
    private func getCurrentFocusedElement() -> AXUIElement? {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let pid = focusedApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let element = focusedElement {
            return element as! AXUIElement
        }
        
        return nil
    }
    
    private func captureFullDocumentText() {
        let separator = String(repeating: "=", count: 60)
        print("\n" + separator)
        print("STEP 1: CAPTURING FULL DOCUMENT TEXT")
        print(separator)
        
        // Update current app name first
        currentApp = getCurrentAppName()
        print("Current app: \(currentApp)")
        
        guard let element = getCurrentFocusedElement() else {
            print("❌ STEP 1 FAILED: Could not capture document text - no focused element")
            print("❌ Trying fallback: screenshot + OCR")
            let ocrText = screenCaptureManager.captureScreenText()
            if !ocrText.isEmpty {
                fullDocumentText = ocrText
                print("✅ STEP 1 FALLBACK SUCCESS: Captured via Screen Capture + OCR: \(fullDocumentText.count) characters")
                print("STEP 1 COMPLETE: fullDocumentText.count = \(fullDocumentText.count)")
                print(separator + "\n")
            } else {
                print("❌ STEP 1 FALLBACK FAILED: Screenshot + OCR also failed")
                print("❌ fullDocumentText.count = 0")
                print(separator + "\n")
            }
            return
        }
        
        print("✅ STEP 1: Got focused element")
        
        // For web browsers (Chrome, Safari, etc.), skip directly to screenshot + OCR
        let webBrowserApps = ["Google Chrome", "Safari", "Microsoft Edge", "Firefox", "Brave", "Opera"]
        if webBrowserApps.contains(currentApp) {
            print("⚠️ Web browser detected, skipping to Method 5 (Screenshot + OCR)")
            let ocrText = screenCaptureManager.captureScreenText()
            if !ocrText.isEmpty {
                fullDocumentText = ocrText
                print("✅ STEP 1 SUCCESS (Method 5): Captured via Screen Capture + OCR: \(fullDocumentText.count) characters")
                print("STEP 1 COMPLETE: fullDocumentText.count = \(fullDocumentText.count)")
                print(separator + "\n")
                return
            } else {
                print("❌ STEP 1 FAILED: OCR failed for web browser")
                print("❌ fullDocumentText.count = 0")
                print(separator + "\n")
                return
            }
        }
        
        // Method 1: Try direct value attribute
        var fullText: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullText)
        
        print("Method 1 (direct value) result: \(result.rawValue)")
        
        if result == .success, let text = fullText as? String, !text.isEmpty {
            fullDocumentText = text
            print("✅ STEP 1 SUCCESS (Method 1): Captured via direct value: \(text.count) characters")
            print("STEP 1 COMPLETE: fullDocumentText.count = \(fullDocumentText.count)")
            print(separator + "\n")
            return
        }
        
        print("⚠️ Method 1 failed, trying Method 5: Screen Capture + OCR")
        
        // Method 5: Capture screenshot and OCR it (works for all apps)
        let ocrText = screenCaptureManager.captureScreenText()
        
        if !ocrText.isEmpty {
            fullDocumentText = ocrText
            print("✅ STEP 1 SUCCESS (Method 5): Captured via Screen Capture + OCR: \(fullDocumentText.count) characters")
            print("STEP 1 COMPLETE: fullDocumentText.count = \(fullDocumentText.count)")
            print(separator + "\n")
            return
        }
        
        print("❌ STEP 1 FAILED: Screenshot + OCR failed")
        print("❌ fullDocumentText.count = 0")
        print(separator + "\n")
    }
    
    private func getSelectedText() -> String? {
        guard let element = getCurrentFocusedElement() else {
            return nil
        }
        
        var selectedText: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        
        if result == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }
        
        // Fallback: try to get selection range and extract from full text
        return getSelectedTextFromSelectionRange()
    }
    
    private func getSelectedTextFromSelectionRange() -> String? {
        guard let element = getCurrentFocusedElement() else {
            return nil
        }
        
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        
        if rangeResult == .success, let range = selectedRange {
            var location: CFIndex = 0
            var length: CFIndex = 0
            if AXValueGetValue(range as! AXValue, .cfRange, &location) && AXValueGetValue(range as! AXValue, .cfRange, &length) {
                let startIndex = fullDocumentText.index(fullDocumentText.startIndex, offsetBy: location)
                let endIndex = fullDocumentText.index(startIndex, offsetBy: length)
                return String(fullDocumentText[startIndex..<endIndex])
            }
        }
        
        return nil
    }
    
    private func extractContext(for term: String, from text: String) -> String {
        if text.isEmpty {
            return ""
        }
        
        // Find all occurrences of the term
        let termLower = term.lowercased()
        let textLower = text.lowercased()
        
        var occurrences: [Range<String.Index>] = []
        var searchRange = textLower.startIndex..<textLower.endIndex
        
        while let range = textLower.range(of: termLower, range: searchRange) {
            occurrences.append(range)
            searchRange = range.upperBound..<textLower.endIndex
        }
        
        guard !occurrences.isEmpty else {
            // If term not found, return the most substantial sections
            return extractSubstantialSections(from: text)
        }
        
        // Select the occurrence closest to the middle of the text
        let middleIndex = textLower.index(textLower.startIndex, offsetBy: textLower.count / 2)
        var closestOccurrence = occurrences[0]
        var closestDistance = abs(textLower.distance(from: middleIndex, to: closestOccurrence.lowerBound))
        
        for occurrence in occurrences {
            let distance = abs(textLower.distance(from: middleIndex, to: occurrence.lowerBound))
            if distance < closestDistance {
                closestDistance = distance
                closestOccurrence = occurrence
            }
        }
        
        // Extract context around the term (4-5 paragraphs)
        let contextRange = getContextRange(around: closestOccurrence, in: text)
        
        return String(text[contextRange])
    }
    
    private func getContextRange(around occurrence: Range<String.Index>, in text: String) -> Range<String.Index> {
        let maxContextLength = 3000
        let halfLength = maxContextLength / 2
        
        let start = text.index(occurrence.lowerBound, offsetBy: -halfLength, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(occurrence.upperBound, offsetBy: halfLength, limitedBy: text.endIndex) ?? text.endIndex
        
        return start..<end
    }
    
    private func extractSubstantialSections(from text: String) -> String {
        // Split into paragraphs and find the longest ones
        let paragraphs = text.components(separatedBy: .newlines)
        let sortedParagraphs = paragraphs.sorted { $0.count > $1.count }
        
        // Return the top paragraphs, up to 2500 characters
        var result = ""
        for paragraph in sortedParagraphs where paragraph.count > 50 {
            if result.count + paragraph.count > 2500 {
                break
            }
            result += paragraph + "\n"
        }
        
        if result.isEmpty && text.count <= 2500 {
            return text
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}