import Foundation
import Testing
@testable import UsageCore

@Suite struct LocalizationTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func agoInBothLanguages() {
        #expect(Format.ago(now - 10, now: now, lang: .ko) == "방금")
        #expect(Format.ago(now - 10, now: now, lang: .en) == "just now")
        #expect(Format.ago(now - 180, now: now, lang: .en) == "3m ago")
        #expect(Format.ago(now - 7200, now: now, lang: .ko) == "2시간 전")
        #expect(Format.ago(now - 86400 * 2, now: now, lang: .en) == "2d ago")
    }

    @Test func resetAtUsesLanguageWeekday() throws {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 29; c.hour = 4   // 화요일
        let d = try #require(Calendar.current.date(from: c))
        #expect(Format.resetAt(d, lang: .ko) == "9/29 (화) 04:00")
        #expect(Format.resetAt(d, lang: .en) == "9/29 (Tue) 04:00")
    }

    /// 예전 state.json에 한국어 이름으로 저장된 한도도 화면에서는 현재 언어 이름으로 보인다
    @Test func displayNameIgnoresStoredName() {
        let r = LimitRow(kind: .model("Fable"), name: "Fable 주간", percent: 10, resetsAt: nil, isActive: false)
        #expect(r.displayName == LimitNames.modelWeekly("Fable"))
        #expect(LimitNames.modelWeekly("Fable", .en) == "Fable weekly")
        let codex = LimitRow(kind: .codex("codex:300"), name: "Codex 5-hour", percent: 1, resetsAt: nil, isActive: false)
        #expect(codex.displayName == "Codex 5-hour")
    }

    /// 오류 코드는 언어와 무관하게 저장하고, 예전 한국어 값도 알아본다
    @Test func fetchErrorDescriptions() {
        #expect(FetchError.describe(FetchError.format) == L("응답 형식 변경", "response format changed"))
        #expect(FetchError.describe("응답 형식 변경") == FetchError.describe(FetchError.format))
        #expect(FetchError.describe("HTTP 500") == "HTTP 500")
    }
}
