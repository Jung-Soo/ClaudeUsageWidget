import Foundation

public enum UsageAPIError: Error, Equatable {
    case unauthorized(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int, String)
    case decoding(String)
    case network(String)
}

public protocol UsageFetching: Sendable {
    func fetch(token: String, now: Date) async throws -> UsageSnapshot
}

public struct UsageAPIClient: UsageFetching {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public var session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(token: String, now: Date) async throws -> UsageSnapshot {
        var req = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-usage-bar/0.1", forHTTPHeaderField: "User-Agent")

        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw UsageAPIError.network(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw UsageAPIError.network("no HTTP response") }

        switch http.statusCode {
        case 200:
            do { return try UsageResponse.decode(data, fetchedAt: now) } catch { throw UsageAPIError.decoding("\(error)") }
        case 401, 403:
            throw UsageAPIError.unauthorized(http.statusCode)
        case 429:
            let ra = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageAPIError.rateLimited(retryAfter: ra)
        default:
            let body = String(decoding: data.prefix(200), as: UTF8.self)
            throw UsageAPIError.http(http.statusCode, Redact.secrets(body))
        }
    }
}

public enum Redact {
    /// `sk-ant-oat01-abcdef…` → `sk-ant-oat01-***`
    public static func secrets(_ s: String) -> String {
        s.replacingOccurrences(of: #"(sk-ant-[A-Za-z0-9_\-]{6})[A-Za-z0-9_\-]+"#,
                               with: "$1***", options: .regularExpression)
    }
}
