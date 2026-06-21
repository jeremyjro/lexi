import Foundation

struct ExplainErrorResponse: Decodable {
    let error: String
}

struct ProxyTiming: Decodable {
    let proxyTtftMs: Int?
    let anthropicTtftMs: Int?
}

final class ExplainClient {
    private let endpoint = URL(string: "http://127.0.0.1:8787/explain")!

    func explain(
        _ capture: CapturedSelection,
        onDelta: @escaping @MainActor (String, String) -> Void,
        onTiming: @escaping @MainActor (ProxyTiming) -> Void
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ExplainPayload(capture: capture))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplainClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorBody = Data()
            for try await byte in bytes {
                errorBody.append(byte)
            }
            if let error = try? JSONDecoder().decode(ExplainErrorResponse.self, from: errorBody) {
                throw ExplainClientError.proxyError(error.error)
            }
            throw ExplainClientError.httpStatus(httpResponse.statusCode)
        }

        var parser = SSEParser()
        var answer = ""

        for try await byte in bytes {
            guard !Task.isCancelled else { throw CancellationError() }
            let events = parser.consume(byte: byte)
            for event in events {
                switch event.name {
                case "delta":
                    let delta = try decode(SSEDelta.self, from: event.data).text
                    answer += delta
                    await onDelta(delta, answer)
                case "timing":
                    await onTiming(try decode(ProxyTiming.self, from: event.data))
                case "error":
                    let error = try decode(SSEError.self, from: event.data)
                    throw ExplainClientError.proxyError(error.message)
                default:
                    continue
                }
            }
        }

        for event in parser.finish() {
            switch event.name {
            case "delta":
                let delta = try decode(SSEDelta.self, from: event.data).text
                answer += delta
                await onDelta(delta, answer)
            case "timing":
                await onTiming(try decode(ProxyTiming.self, from: event.data))
            case "error":
                let error = try decode(SSEError.self, from: event.data)
                throw ExplainClientError.proxyError(error.message)
            default:
                continue
            }
        }

        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: String) throws -> T {
        guard let payload = data.data(using: .utf8) else {
            throw ExplainClientError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: payload)
    }
}

private struct ExplainPayload: Encodable {
    let term: String
    let passage: String
    let windowTitle: String
    let appName: String

    init(capture: CapturedSelection) {
        term = capture.term
        passage = capture.passage
        windowTitle = capture.windowTitle
        appName = capture.appName
    }
}

private struct SSEEvent {
    let name: String
    let data: String
}

private struct SSEParser {
    private var buffer = Data()
    private let separator = Data([10, 10])

    mutating func consume(byte: UInt8) -> [SSEEvent] {
        buffer.append(byte)
        return drainCompleteEvents()
    }

    mutating func finish() -> [SSEEvent] {
        guard !buffer.isEmpty else { return [] }
        defer { buffer.removeAll(keepingCapacity: true) }
        guard let text = String(data: buffer, encoding: .utf8), let event = parseEvent(text) else { return [] }
        return [event]
    }

    private mutating func drainCompleteEvents() -> [SSEEvent] {
        var events: [SSEEvent] = []

        while let range = buffer.range(of: separator) {
            let eventData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)

            guard !eventData.isEmpty,
                  let text = String(data: eventData, encoding: .utf8),
                  let event = parseEvent(text) else { continue }
            events.append(event)
        }

        return events
    }

    private func parseEvent(_ text: String) -> SSEEvent? {
        var name = "message"
        var dataLines: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix("event: ") {
                name = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                dataLines.append(String(line.dropFirst(6)))
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(name: name, data: dataLines.joined(separator: "\n"))
    }
}

private struct SSEDelta: Decodable {
    let text: String
}

private struct SSEError: Decodable {
    let message: String
}

enum ExplainClientError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case proxyError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Lexi proxy."
        case .httpStatus(let status):
            return "Lexi proxy returned HTTP \(status)."
        case .proxyError(let message):
            return message
        }
    }
}
