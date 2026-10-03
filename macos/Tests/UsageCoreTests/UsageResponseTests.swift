import Foundation
import Testing
@testable import UsageCore

@Suite struct UsageResponseTests {
    @Test func liveFixture() throws {
        let s = try UsageResponse.decode(Fx.data("usage-live-2026-09-29.json"), fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(s.fiveHour?.percent == 2)
        #expect(s.fiveHour?.resetsAt == date("2026-09-29T07:29:59.528Z"))
        #expect(s.fiveHour?.isActive == false)
        #expect(s.weekly?.percent == 25)
        #expect(s.weekly?.isActive == true)
        #expect(s.models.map(\.displayName) == [LimitNames.modelWeekly("Fable")])
        #expect(s.models.first?.percent == 11)
        #expect(s.credit == Credit(enabled: true, used: 4.89, limit: 50, currency: "USD", percent: 9.78))
    }

    @Test func fallsBackToLimitsWhenWindowsAreNull() throws {
        let json = """
        {"five_hour": null, "seven_day": null,
         "limits": [
           {"kind": "session", "percent": 40, "resets_at": "2026-09-29T07:00:00Z", "is_active": true},
           {"kind": "weekly_all", "percent": 10},
           {"kind": "weekly_scoped", "percent": 5, "scope": {"model": {"display_name": "Opus"}}},
           {"kind": "weekly_scoped", "percent": 30, "scope": {"model": {"display_name": "Sonnet"}}},
           {"kind": 42, "percent": "broken"}
         ]}
        """
        let s = try UsageResponse.decode(Data(json.utf8), fetchedAt: .now)
        #expect(s.fiveHour?.percent == 40)
        #expect(s.fiveHour?.isActive == true)
        #expect(s.weekly?.percent == 10)
        #expect(s.models.map(\.displayName) == ["Sonnet", "Opus"].map { LimitNames.modelWeekly($0) })   // 높은 순
    }

    @Test func spendIsUsedWhenExtraUsageMissing() throws {
        let json = """
        {"spend": {"used": {"amount_minor": 1234, "currency": "USD", "exponent": 2},
                   "limit": {"amount_minor": 10000, "exponent": 2}, "percent": 12, "enabled": true}}
        """
        let s = try UsageResponse.decode(Data(json.utf8), fetchedAt: .now)
        #expect(s.credit == Credit(enabled: true, used: 12.34, limit: 100, currency: "USD", percent: 12))
        #expect(s.rows.isEmpty)
    }

    @Test func parsesDates() {
        #expect(ISODate.parse("2026-09-29T07:29:59.528548+00:00") == date("2026-09-29T07:29:59.528Z"))
        #expect(ISODate.parse("2026-09-29T07:29:59Z") != nil)
        #expect(ISODate.parse("2026-09-29T07:29:59.5Z") == date("2026-09-29T07:29:59.500Z"))
        #expect(ISODate.parse("1790649895441") == Date(timeIntervalSince1970: 1790649895.441))
        #expect(ISODate.parse("") == nil)
    }

    @Test func redactsTokens() {
        #expect(Redact.secrets("bad token sk-ant-oat01-AbCdEf_123-xyz here") == "bad token sk-ant-oat01-*** here")
    }
}

@Suite struct CredentialTests {
    @Test func parsesKeychainJSON() {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-x","refreshToken":"r","expiresAt":1790650000000,"subscriptionType":"team","rateLimitTier":"default_claude_max_5x"},"mcpOAuth":{}}"#
        let c = OAuthCredential.parse(Data(json.utf8))
        #expect(c?.accessToken == "sk-ant-oat01-x")
        #expect(c?.expiresAt == Date(timeIntervalSince1970: 1790650000))
        #expect(c?.planLabel == "Team · Max 5x")
        #expect(c?.isExpired(at: Date(timeIntervalSince1970: 1790649950)) == true)   // 만료 50초 전이면 60초 여유에 걸림
        #expect(c?.isExpired(at: Date(timeIntervalSince1970: 1790640000)) == false)
    }

    @Test func planLabels() {
        func label(_ s: String?, _ t: String?) -> String? {
            OAuthCredential(accessToken: "x", subscriptionType: s, rateLimitTier: t).planLabel
        }
        #expect(label("max", "default_claude_max_20x") == "Max 20x")
        #expect(label("pro", nil) == "Pro")
        #expect(label(nil, nil) == nil)
    }

    @Test func missingTokenIsNil() {
        #expect(OAuthCredential.parse(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil)
        #expect(OAuthCredential.parse(Data("not json".utf8)) == nil)
    }
}
