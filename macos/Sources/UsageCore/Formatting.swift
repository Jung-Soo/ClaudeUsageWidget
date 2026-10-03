import Foundation

public enum Format {
    /// 리셋까지 남은 시간: "4일 3시간" / "2시간 14분" / "38분" / "곧" (영어: "4d 3h" / "2h 14m" / "38m" / "soon")
    public static func left(until date: Date?, now: Date, lang: Lang = .current) -> String? {
        guard let date else { return nil }
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 { return soon(lang) }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d >= 1 { return L("\(d)일 \(h)시간", "\(d)d \(h)h", lang: lang) }
        if h >= 1 { return L("\(h)시간 \(m)분", "\(h)h \(m)m", lang: lang) }
        return L("\(max(1, m))분", "\(max(1, m))m", lang: lang)
    }

    /// `left`가 0초 이하일 때 돌려주는 값
    public static func soon(_ lang: Lang = .current) -> String { L("곧", "soon", lang: lang) }

    /// 리셋 시각: "9/30 (화) 04:00" / "9/30 (Tue) 04:00"
    public static func resetAt(_ date: Date?, short: Bool = false, lang: Lang = .current) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.locale = lang.locale
        f.dateFormat = short ? "M/d HH:mm" : "M/d (E) HH:mm"
        return f.string(from: date)
    }

    /// "3분 전" / "방금" (영어: "3m ago" / "just now")
    public static func ago(_ date: Date, now: Date, lang: Lang = .current) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return L("방금", "just now", lang: lang) }
        if s < 3600 { return L("\(s / 60)분 전", "\(s / 60)m ago", lang: lang) }
        if s < 86400 { return L("\(s / 3600)시간 전", "\(s / 3600)h ago", lang: lang) }
        return L("\(s / 86400)일 전", "\(s / 86400)d ago", lang: lang)
    }

    public static func tokens(_ n: Int64) -> String {
        let d = Double(n)
        if d >= 1e9 { return String(format: "%.2fB", d / 1e9) }
        if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
        if d >= 1e3 { return String(format: "%.1fK", d / 1e3) }
        return "\(n)"
    }

    public static func money(_ v: Double?, currency: String) -> String? {
        guard let v else { return nil }
        if currency == "USD" { return String(format: "$%.2f", v) }
        return String(format: "%.2f %@", v, currency)
    }

    public static func percent(_ p: Double) -> String { "\(Int(p.rounded()))" }
}
