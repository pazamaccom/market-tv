import Foundation

enum APIError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case notJSON

    var errorDescription: String? {
        switch self {
        case .badURL(let s): return "Invalid address: \(s)"
        case .http(let code, let body): return "Server answered HTTP \(code). \(body)"
        case .notJSON: return "The server did not return JSON."
        }
    }
}

/// Read-only GET requests to the private dashboards. No caching, short timeout.
enum API {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// For the Market Health daily record (/api/latest, about 10 MB uncompressed in Oct 2026).
    private static let largeSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 45
        c.timeoutIntervalForResource = 120
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func data(_ base: String, _ path: String, large: Bool = false) async throws -> Data {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed + path), url.scheme != nil else { throw APIError.badURL(trimmed + path) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await (large ? largeSession : session).data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw APIError.http(code, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }

    static func parse(_ data: Data) throws -> J {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { throw APIError.notJSON }
        return J(object)
    }

    static func describe(_ error: Error) -> String {
        if let u = error as? URLError {
            switch u.code {
            case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost,
                 .notConnectedToInternet, .dnsLookupFailed, .cannotLoadFromNetwork:
                return "Cannot reach trader-node. Check that Tailscale is connected on this Apple TV and allowed to reach the dashboard. (\(u.code.rawValue))"
            default:
                return u.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
