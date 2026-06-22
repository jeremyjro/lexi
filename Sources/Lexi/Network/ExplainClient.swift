import Foundation

struct ExplainErrorResponse: Decodable {
    let code: String?
    let error: String
}

struct ProxyHealth: Decodable {
    let ok: Bool
    let model: String
    let anthropicApiKeyConfigured: Bool?
    let proxyTokenConfigured: Bool?
}

struct ProxyTiming: Decodable {
    let proxyTtftMs: Int?
    let anthropicTtftMs: Int?
}

final class ExplainClient {
    private let proxyBaseURL: URL
    private let proxyToken: String?

    init(configuration: AppConfiguration = .current) {
        proxyBaseURL = configuration.proxyBaseURL
        proxyToken = configuration.proxyToken
    }

    var baseURLDescription: String {
        proxyBaseURL.absoluteString
    }

    var hasProxyToken: Bool {
        proxyToken != nil
    }

    func health() async throws -> ProxyHealth {
        var request = URLRequest(url: endpoint("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ExplainClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ExplainClientError.httpStatus(httpResponse.statusCode)
            }
            return try JSONDecoder().decode(ProxyHealth.self, from: data)
        } catch let error as ExplainClientError {
            throw error
        } catch {
            throw ExplainClientError.proxyUnavailable(proxyBaseURL.absoluteString)
        }
    }

    func explain(
        _ capture: CapturedSelection,
        onDelta: @escaping @MainActor (String, String) -> Void,
        onTiming: @escaping @MainActor (ProxyTiming) -> Void
    ) async throws -> String {
        try await performExplain(
            payload: ExplainPayload(capture: capture),
            onDelta: onDelta,
            onTiming: onTiming
        )
    }

    func explainNested(
        term: String,
        in stack: LookupNavigationStack,
        onDelta: @escaping @MainActor (String, String) -> Void,
        onTiming: @escaping @MainActor (ProxyTiming) -> Void
    ) async throws -> String {
        guard let root = stack.rootNode, let parent = stack.currentNode else {
            throw ExplainClientError.invalidResponse
        }

        let payload = ExplainPayload(
            term: term,
            passage: parent.answer,
            windowTitle: parent.windowTitle,
            appName: "Lexi",
            lineage: ExplainLineagePayload(
                rootTerm: root.term,
                rootSourceText: root.sourceText,
                parentTerm: parent.term,
                parentAnswer: parent.answer,
                depth: stack.depth + 1
            )
        )

        return try await performExplain(payload: payload, onDelta: onDelta, onTiming: onTiming)
    }

    private func performExplain(
        payload: ExplainPayload,
        onDelta: @escaping @MainActor (String, String) -> Void,
        onTiming: @escaping @MainActor (ProxyTiming) -> Void
    ) async throws -> String {
        var request = URLRequest(url: endpoint("explain"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyProxyAuthorization(to: &request)
        request.httpBody = try JSONEncoder().encode(payload)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw ExplainClientError.proxyUnavailable(proxyBaseURL.absoluteString)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplainClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorBody = Data()
            for try await byte in bytes {
                errorBody.append(byte)
            }
            if let error = try? JSONDecoder().decode(ExplainErrorResponse.self, from: errorBody) {
                throw ExplainClientError.proxyError(code: error.code, message: error.error)
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
                    throw ExplainClientError.proxyError(code: error.code, message: error.message)
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
                throw ExplainClientError.proxyError(code: error.code, message: error.message)
            default:
                continue
            }
        }

        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func endpoint(_ path: String) -> URL {
        proxyBaseURL.appendingPathComponent(path)
    }

    private func applyProxyAuthorization(to request: inout URLRequest) {
        guard let proxyToken else { return }
        request.setValue("Bearer \(proxyToken)", forHTTPHeaderField: "Authorization")
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
    let lineage: ExplainLineagePayload?

    init(capture: CapturedSelection) {
        term = capture.term
        passage = capture.passage
        windowTitle = capture.windowTitle
        appName = capture.appName
        lineage = nil
    }

    init(term: String, passage: String, windowTitle: String, appName: String, lineage: ExplainLineagePayload?) {
        self.term = term
        self.passage = passage
        self.windowTitle = windowTitle
        self.appName = appName
        self.lineage = lineage
    }
}

private struct ExplainLineagePayload: Encodable {
    let rootTerm: String
    let rootSourceText: String
    let parentTerm: String
    let parentAnswer: String
    let depth: Int
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
    let code: String?
    let message: String
}

enum ExplainClientError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case proxyError(code: String?, message: String)
    case proxyUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Lexi received an invalid response from the proxy."
        case .httpStatus(let status):
            return httpStatusMessage(status)
        case .proxyError(let code, let message):
            return proxyErrorMessage(code: code, fallback: message)
        case .proxyUnavailable(let url):
            return "Lexi proxy is not reachable at \(url). Check your internet connection or proxy URL in Settings."
        }
    }

    private func httpStatusMessage(_ status: Int) -> String {
        switch status {
        case 400:
            return "Lexi sent an invalid request to the proxy. Try a shorter selection."
        case 401, 403:
            return "Lexi proxy rejected the request. Check the proxy token in Settings."
        case 404:
            return "Lexi proxy endpoint was not found. Check the proxy URL in Settings."
        case 429:
            return "Lexi proxy is rate limited. Try again shortly."
        case 500...599:
            return "Lexi proxy is having a server issue. Check Railway health or try again shortly."
        default:
            return "Lexi proxy returned HTTP \(status)."
        }
    }

    private func proxyErrorMessage(code: String?, fallback: String) -> String {
        switch code {
        case "unauthorized":
            return "Lexi proxy rejected the request. Check the proxy token in Settings."
        case "invalid_request":
            return "Lexi could not send this selection. Try selecting a shorter phrase."
        case "assistant_misconfigured":
            return "The assistant backend is missing its Anthropic API key. Check Railway variables."
        case "assistant_auth_failed":
            return "The assistant API key was rejected. Check the Anthropic key in Railway."
        case "assistant_model_unavailable":
            return "The configured assistant model is unavailable. Check ANTHROPIC_MODEL in Railway."
        case "assistant_rate_limited":
            return "The assistant is rate limited. Try again shortly."
        case "assistant_overloaded":
            return "The assistant is overloaded. Try again shortly."
        case "assistant_unavailable":
            return "The assistant service is unavailable. Try again shortly."
        default:
            return fallback
        }
    }
}
