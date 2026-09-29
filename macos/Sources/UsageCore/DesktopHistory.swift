import Foundation

/// Claude 데스크톱 앱이 15분마다 남기는 사용률 기록 한 점.
public struct DesktopSample: Sendable, Equatable, Codable {
    public var t: Date
    public var fiveHour: Double?
    public var weekly: Double?
    public var extra: Double?
}

public protocol DesktopHistoryReading: Sendable {
    func samples() -> [DesktopSample]
}

extension DesktopHistoryReading {
    public func latest() -> DesktopSample? { samples().max { $0.t < $1.t } }
}

/// `~/Library/Application Support/Claude/plan-usage-history.json` (데스크톱 앱 내부 파일, version 2만 해석).
public struct DesktopHistoryReader: DesktopHistoryReading {
    public static let supportedVersion = 2
    public var url: URL

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")) {
        self.url = url
    }

    public func samples() -> [DesktopSample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return Self.parse(data)
    }

    public static func parse(_ data: Data) -> [DesktopSample] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["version"] as? Int == supportedVersion,
              let arr = obj["samples"] as? [[String: Any]] else { return [] }
        return arr.compactMap { s in
            guard let t = s["t"] as? Double, let u = s["u"] as? [String: Any] else { return nil }
            return DesktopSample(t: Date(timeIntervalSince1970: t / 1000),
                                 fiveHour: u["fh"] as? Double, weekly: u["sd"] as? Double, extra: u["xu"] as? Double)
        }
    }
}
