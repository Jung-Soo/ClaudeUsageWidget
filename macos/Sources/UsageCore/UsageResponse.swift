import Foundation

/// `/api/oauth/usage` 응답. 문서화되지 않은 API라 모든 필드를 옵셔널로 받고,
/// 배열 원소 하나가 깨져도 나머지는 살린다.
struct RawUsage: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    struct Limit: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable { let display_name: String? }
            let model: Model?
        }
        let kind: String?
        let percent: Double?
        let severity: String?
        let resets_at: String?
        let is_active: Bool?
        let scope: Scope?
    }

    struct Extra: Decodable {
        let is_enabled: Bool?
        let monthly_limit: Double?
        let used_credits: Double?
        let utilization: Double?
        let currency: String?
        let decimal_places: Int?
    }

    struct Spend: Decodable {
        struct Money: Decodable {
            let amount_minor: Double?
            let currency: String?
            let exponent: Int?
        }
        let used: Money?
        let limit: Money?
        let percent: Double?
        let enabled: Bool?
    }

    let five_hour: Window?
    let seven_day: Window?
    let limits: Lossy<Limit>?
    let extra_usage: Extra?
    let spend: Spend?
}

struct Lossy<Element: Decodable>: Decodable {
    let items: [Element]

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !c.isAtEnd {
            if let v = try? c.decode(Element.self) { out.append(v) } else { _ = try? c.decode(Skip.self) }
        }
        items = out
    }
}

public enum UsageResponse {
    public static func decode(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        let raw = try JSONDecoder().decode(RawUsage.self, from: data)
        return map(raw, fetchedAt: fetchedAt)
    }

    static func map(_ r: RawUsage, fetchedAt: Date) -> UsageSnapshot {
        let limits = r.limits?.items ?? []
        let session = limits.first { $0.kind == "session" }
        let weeklyAll = limits.first { $0.kind == "weekly_all" }

        func row(_ kind: LimitKind, _ name: String, window: RawUsage.Window?, fallback: RawUsage.Limit?) -> LimitRow? {
            let pct = window?.utilization ?? fallback?.percent
            guard let pct else { return nil }
            let reset = ISODate.parse(window?.resets_at ?? fallback?.resets_at)
            return LimitRow(kind: kind, name: name, percent: pct, resetsAt: reset,
                            isActive: fallback?.is_active ?? false, severity: fallback?.severity)
        }

        let five = row(.session, "5시간", window: r.five_hour, fallback: session)
        let week = row(.weekly, "주간", window: r.seven_day, fallback: weeklyAll)
        let models = limits
            .filter { $0.kind == "weekly_scoped" }
            .compactMap { l -> LimitRow? in
                guard let p = l.percent else { return nil }
                let m = l.scope?.model?.display_name.flatMap { $0.isEmpty ? nil : $0 } ?? "모델"
                return LimitRow(kind: .model(m), name: "\(m) 주간", percent: p,
                                resetsAt: ISODate.parse(l.resets_at), isActive: l.is_active ?? false, severity: l.severity)
            }
            .sorted { $0.percent > $1.percent }

        return UsageSnapshot(fiveHour: five, weekly: week, models: models, credit: credit(r), fetchedAt: fetchedAt)
    }

    static func credit(_ r: RawUsage) -> Credit? {
        if let e = r.extra_usage {
            let div = pow(10, Double(e.decimal_places ?? 2))
            let used = e.used_credits.map { $0 / div }
            let limit = e.monthly_limit.map { $0 / div }
            var pct = e.utilization
            if pct == nil, let u = used, let l = limit, l > 0 { pct = 100 * u / l }
            return Credit(enabled: e.is_enabled ?? false, used: used, limit: limit, currency: e.currency ?? "USD", percent: pct)
        }
        if let s = r.spend {
            func amount(_ m: RawUsage.Spend.Money?) -> Double? {
                guard let m, let a = m.amount_minor else { return nil }
                return a / pow(10, Double(m.exponent ?? 2))
            }
            return Credit(enabled: s.enabled ?? false, used: amount(s.used), limit: amount(s.limit),
                          currency: s.used?.currency ?? "USD", percent: s.percent)
        }
        return nil
    }
}
