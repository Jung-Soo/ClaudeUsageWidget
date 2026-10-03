import Foundation

/// 표시 언어. 한국어 환경이면 한국어, 그 밖에는 영어.
/// 우선순위: 환경변수 `CUB_LANG`(스냅샷·점검용) → 설정의 언어(`language`, 재시작 후 적용) → 시스템 언어.
public enum Lang: String, Sendable, CaseIterable {
    case ko, en

    public static let current: Lang = {
        if let v = ProcessInfo.processInfo.environment["CUB_LANG"], let l = Lang(rawValue: v) { return l }
        if let v = UserDefaults.standard.string(forKey: "language"), let l = Lang(rawValue: v) { return l }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko") ? .ko : .en
    }()

    var locale: Locale { Locale(identifier: self == .ko ? "ko_KR" : "en_US") }
}

/// 문구를 두 언어로 나란히 적는다: `L("지금 갱신", "Refresh now")`.
public func L(_ ko: String, _ en: String, lang: Lang = .current) -> String {
    lang == .ko ? ko : en
}

/// 한도 이름. state.json에 저장된 이름(예전 언어)이 아니라 종류에서 매번 만든다.
public enum LimitNames {
    public static func fiveHour(_ lang: Lang = .current) -> String { L("5시간", "5-hour", lang: lang) }
    public static func weekly(_ lang: Lang = .current) -> String { L("주간", "Weekly", lang: lang) }
    public static func modelWeekly(_ model: String, _ lang: Lang = .current) -> String {
        L("\(model) 주간", "\(model) weekly", lang: lang)
    }
}

extension LimitRow {
    /// 화면·알림에 쓰는 이름. Codex 한도는 매번 새로 만들어지므로 `name`을 그대로 쓴다.
    public var displayName: String {
        switch kind {
        case .session: LimitNames.fiveHour()
        case .weekly: LimitNames.weekly()
        case .model(let m): LimitNames.modelWeekly(m)
        case .codex: name
        }
    }
}

/// `FetchStatus.error`에 저장하는 값. state.json에 남으므로 언어와 무관한 코드로 두고, 보여 줄 때 바꾼다.
public enum FetchError {
    public static let format = "format"
    public static let network = "network"

    public static func describe(_ code: String) -> String {
        switch code {
        case format, "응답 형식 변경": L("응답 형식 변경", "response format changed")
        case network, "네트워크": L("네트워크", "network")
        default: code
        }
    }
}
