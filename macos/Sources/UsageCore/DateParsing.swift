import Foundation

enum ISODate {
    /// API는 `2026-09-29T07:29:59.528548+00:00`처럼 소수점 6자리를 주고, 세션 로그는 `…00.000Z`를 쓴다.
    /// ISO8601DateFormatter는 소수점 3자리까지만 안정적으로 읽으므로 잘라서 넘긴다.
    static func parse(_ raw: String?) -> Date? {
        guard var s = raw, !s.isEmpty else { return nil }
        if let n = Double(s) { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        if let dot = s.firstIndex(of: "."), let t = s.firstIndex(of: "T"), dot > t {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            let digits = s[s.index(after: dot)..<end]
            let kept = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            s.replaceSubrange(s.index(after: dot)..<end, with: kept)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s)
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
