import Foundation

public enum DataSource: Sendable, Equatable {
    case api
    case desktopHistory
    case none
}

/// 화면에 그릴 최종 상태.
public struct DisplayState: Sendable, Equatable {
    public var rows: [LimitRow] = []
    public var credit: Credit?
    public var source: DataSource = .none
    /// 표시 중인 값의 기준 시각.
    public var asOf: Date?
    /// 값이 최신이 아닌 행(회색으로 그린다).
    public var staleRowIDs: Set<String> = []
    public var status: FetchStatus = .idle
    public var plan: String?

    public init() {}

    public var fiveHour: LimitRow? { rows.first { $0.kind == .session } }
    public var weekly: LimitRow? { rows.first { $0.kind == .weekly } }
    public var models: [LimitRow] { rows.filter { if case .model = $0.kind { true } else { false } } }

    /// 지금 걸린 한도. 서버가 표시한 게 없으면 가장 높은 것.
    public var active: LimitRow? { rows.first { $0.isActive } ?? rows.max { $0.percent < $1.percent } }
    public var others: [LimitRow] { rows.filter { $0.id != active?.id } }
    public func isStale(_ row: LimitRow) -> Bool { staleRowIDs.contains(row.id) }
}

/// API 스냅샷과 데스크톱 앱 기록 중 무엇을 보여 줄지 정한다(02-spike-result.md 5.1).
public enum DisplayResolver {
    /// 데스크톱 기록은 15분 주기라 30분 안이면 최신으로 본다.
    public static let desktopFreshness: TimeInterval = 30 * 60

    public static func apiFreshness(interval: TimeInterval) -> TimeInterval { max(FetchPolicy.clamp(interval) * 2.5, 600) }

    public static func resolve(api: UsageSnapshot?, desktop: DesktopSample?, status: FetchStatus,
                               plan: String?, now: Date, interval: TimeInterval) -> DisplayState {
        var d = DisplayState()
        d.status = status
        d.plan = plan

        let apiFresh = api.map { now.timeIntervalSince($0.fetchedAt) <= apiFreshness(interval: interval) } ?? false
        let desktopFresh = desktop.map { now.timeIntervalSince($0.t) <= desktopFreshness } ?? false
        let desktopNewer = desktop.map { s in api.map { s.t > $0.fetchedAt } ?? true } ?? false

        if let api, apiFresh {
            d.rows = api.rows
            d.credit = api.credit
            d.source = .api
            d.asOf = api.fetchedAt
        } else if let desktop, desktopFresh, desktopNewer {
            d = merge(desktop: desktop, cached: api, now: now, base: d)
        } else if let api {
            d.rows = api.rows
            d.credit = api.credit
            d.source = .api
            d.asOf = api.fetchedAt
            d.staleRowIDs = Set(api.rows.map(\.id))
        } else if let desktop {
            d = merge(desktop: desktop, cached: nil, now: now, base: d)
            d.staleRowIDs = Set(d.rows.map(\.id))
        }
        return d
    }

    /// 데스크톱 기록의 %에, 마지막 API 값에서 리셋 시각(아직 안 지난 것만)과 모델별 한도(회색)를 덧붙인다.
    private static func merge(desktop s: DesktopSample, cached: UsageSnapshot?, now: Date, base: DisplayState) -> DisplayState {
        var d = base
        func future(_ date: Date?) -> Date? { date.flatMap { $0 > now ? $0 : nil } }
        var rows: [LimitRow] = []
        if let p = s.fiveHour {
            rows.append(LimitRow(kind: .session, name: "5시간", percent: p,
                                 resetsAt: future(cached?.fiveHour?.resetsAt), isActive: cached?.fiveHour?.isActive ?? false))
        }
        if let p = s.weekly {
            rows.append(LimitRow(kind: .weekly, name: "주간", percent: p,
                                 resetsAt: future(cached?.weekly?.resetsAt), isActive: cached?.weekly?.isActive ?? false))
        }
        let models = cached?.models ?? []
        rows += models.map { var m = $0; m.resetsAt = future(m.resetsAt); return m }
        d.rows = rows
        d.staleRowIDs = Set(models.map(\.id))
        if var c = cached?.credit {
            if let x = s.extra { c.percent = x }
            d.credit = c
        }
        d.source = .desktopHistory
        d.asOf = s.t
        return d
    }
}
