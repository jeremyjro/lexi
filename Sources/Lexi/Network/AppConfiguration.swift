import Foundation

struct AppConfiguration {
    static let defaultProxyBaseURL = URL(string: "http://127.0.0.1:8787")!

    let proxyBaseURL: URL
    let proxyToken: String?

    static var current: AppConfiguration {
        AppConfiguration(proxyBaseURL: resolvedProxyBaseURL(), proxyToken: resolvedProxyToken())
    }

    private static func resolvedProxyBaseURL() -> URL {
        let defaultsValue = UserDefaults.standard.string(forKey: "LexiProxyBaseURL")
        let environmentValue = ProcessInfo.processInfo.environment["LEXI_PROXY_BASE_URL"]
        let rawValue = [defaultsValue, environmentValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let rawValue, let url = URL(string: rawValue), url.scheme != nil, url.host != nil else {
            return defaultProxyBaseURL
        }

        return url
    }

    private static func resolvedProxyToken() -> String? {
        let defaultsValue = UserDefaults.standard.string(forKey: "LexiProxyToken")
        let environmentValue = ProcessInfo.processInfo.environment["LEXI_PROXY_TOKEN"]
        return [defaultsValue, environmentValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
