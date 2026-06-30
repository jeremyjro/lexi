import AppKit
import ApplicationServices
import Foundation

@MainActor
final class LexiContextSampler {
    private struct ContextEvent: Codable, Equatable {
        let schemaVersion: Int
        let id: UUID
        let createdAt: Date
        let appName: String
        let bundleIdentifier: String
        let processIdentifier: Int
        let windowTitle: String
    }

    private let encoder: JSONEncoder
    private let eventsURL: URL
    private var timer: Timer?
    private var lastSignature = ""

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryURL = baseURL.appendingPathComponent("Lexi", isDirectory: true)
        eventsURL = directoryURL.appendingPathComponent("context-events.jsonl")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func start() {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        guard let application = NSWorkspace.shared.frontmostApplication else { return }
        let event = ContextEvent(
            schemaVersion: 1,
            id: UUID(),
            createdAt: Date(),
            appName: application.localizedName ?? "Unknown",
            bundleIdentifier: application.bundleIdentifier ?? "",
            processIdentifier: Int(application.processIdentifier),
            windowTitle: Self.frontmostWindowTitle(processIdentifier: application.processIdentifier)
        )
        let signature = "\(event.bundleIdentifier)|\(event.windowTitle)"
        guard signature != lastSignature else { return }
        lastSignature = signature
        append(event)
    }

    private func append(_ event: ContextEvent) {
        guard let data = try? encoder.encode(event) else { return }
        if !FileManager.default.fileExists(atPath: eventsURL.path) {
            FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: eventsURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data([10]))
    }

    private static func frontmostWindowTitle(processIdentifier: pid_t) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let window = focusedWindow else { return "" }
        var titleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue) == .success else { return "" }
        return titleValue as? String ?? ""
    }
}
