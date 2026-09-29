import Foundation
import Testing
@testable import UsageCore

@Suite struct CodexTests {
    let now = date("2026-09-29T03:00:00Z")   // 12:00 KST

    /// 실제 로그와 같은 모양의 token_count 줄.
    func line(_ ts: String, id: String?, name: String? = nil, plan: String = "pro",
              primary: (Double, Int, Double)? = nil, secondary: (Double, Int, Double)? = nil) -> String {
        func w(_ v: (Double, Int, Double)?) -> Any {
            guard let v else { return NSNull() }
            return ["used_percent": v.0, "window_minutes": v.1, "resets_at": v.2]
        }
        let rl: [String: Any] = ["limit_id": id as Any? ?? NSNull(), "limit_name": name as Any? ?? NSNull(),
                                 "primary": w(primary), "secondary": w(secondary), "plan_type": plan,
                                 "credits": ["has_credits": false, "unlimited": false, "balance": "0"]]
        let obj: [String: Any] = ["timestamp": ts, "type": "event_msg", "ordinal": 1,
                                  "payload": ["type": "token_count", "info": ["total_token_usage": [:]], "rate_limits": rl]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
    }

    func root(_ files: [String: [String]]) throws -> URL {
        let r = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        for (path, lines) in files {
            let url = r.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        return r
    }

    var weekReset: Double { now.timeIntervalSince1970 + 3 * 86400 }

    @Test func picksLatestRecordPerLimit() throws {
        let r = try root([
            "2026/09/28/rollout-a.jsonl": [
                line("2026-09-28T10:00:00.000Z", id: "codex", primary: (40, 10080, weekReset)),
                #"{"timestamp":"2026-09-28T10:00:01.000Z","type":"response_item","payload":{"type":"message"}}"#,
            ],
            "2026/09/29/rollout-b.jsonl": [
                line("2026-09-29T02:00:00.000Z", id: "codex", primary: (44, 10080, weekReset)),
                line("2026-09-29T02:30:00.000Z", id: "codex", primary: (45, 10080, weekReset)),
                line("2026-09-29T02:31:00.000Z", id: "premium"),
                line("2026-09-29T02:32:00.000Z", id: "codex_bengalfox", name: "GPT-5.3-Codex-Spark",
                     primary: (12, 300, now.timeIntervalSince1970 + 3600), secondary: (30, 10080, weekReset)),
            ],
        ])
        let s = CodexLogReader(root: r, calendar: seoul).read(now: now)
        #expect(s.limits.map(\.id) == ["codex", "codex_bengalfox"])        // 창 없는 premium은 제외, codex가 먼저
        #expect(s.limits.first?.windows.first?.percent == 45)
        #expect(s.observedAt == date("2026-09-29T02:32:00.000Z"))

        let d = try #require(CodexResolver.resolve(s, now: now))
        #expect(d.rows.map(\.name) == ["주간", "GPT-5.3-Codex-Spark 5시간", "GPT-5.3-Codex-Spark 주간"])
        #expect(d.active?.percent == 45)
        #expect(d.plan == "Pro")
        #expect(d.isStale == false)
        #expect(d.rows.first?.id == "codex:codex:10080")
    }

    @Test func dropsOldLimitsAndZeroesPassedWindows() throws {
        let r = try root([
            "2026/09/10/rollout-old.jsonl": [line("2026-09-10T00:00:00.000Z", id: "codex_old", primary: (80, 10080, 0))],
            "2026/09/29/rollout-b.jsonl": [line("2026-09-29T02:00:00.000Z", id: "codex",
                                                 primary: (70, 300, now.timeIntervalSince1970 - 60),
                                                 secondary: (20, 10080, weekReset))],
        ])
        let d = try #require(CodexResolver.resolve(CodexLogReader(root: r, calendar: seoul).read(now: now), now: now))
        #expect(d.rows.map(\.name) == ["5시간", "주간"])                    // 8일 넘은 한도는 안 보임
        #expect(d.rows[0].percent == 0)                                     // 리셋 시각이 지난 창은 0%
        #expect(d.rows[0].resetsAt == nil)
    }

    @Test func staleAfterSixHours() throws {
        let r = try root(["2026/09/28/rollout.jsonl": [line("2026-09-28T18:00:00.000Z", id: "codex", primary: (45, 10080, weekReset))]])
        let d = try #require(CodexResolver.resolve(CodexLogReader(root: r, calendar: seoul).read(now: now), now: now))
        #expect(d.isStale)
    }

    @Test func noDataIsNil() throws {
        let r = try root([:])
        #expect(CodexResolver.resolve(CodexLogReader(root: r, calendar: seoul).read(now: now), now: now) == nil)
    }

    @Test func readsTailOfLargeFileAndCaches() throws {
        let filler = String(repeating: #"{"timestamp":"2026-09-29T01:00:00.000Z","type":"response_item","payload":{"type":"message","text":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}}"#, count: 1)
        var lines = Array(repeating: filler, count: 6000)                 // 약 900KB: 처음 256KB 꼬리에는 기록 없음
        lines.insert(line("2026-09-29T00:59:00.000Z", id: "codex", primary: (33, 10080, weekReset)), at: 0)
        lines.insert(line("2026-09-29T00:59:30.000Z", id: "codex", primary: (34, 10080, weekReset)), at: 1000)
        let r = try root(["2026/09/29/rollout-big.jsonl": lines])
        let reader = CodexLogReader(root: r, calendar: seoul)
        #expect(reader.read(now: now).limits.first?.windows.first?.percent == 34)

        // 같은 파일에 새 기록이 붙으면 다시 읽는다
        let url = r.appendingPathComponent("2026/09/29/rollout-big.jsonl")
        let h = try FileHandle(forWritingTo: url)
        h.seekToEndOfFile()
        h.write(Data((line("2026-09-29T02:50:00.000Z", id: "codex", primary: (36, 10080, weekReset)) + "\n").utf8))
        try h.close()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        #expect(reader.read(now: now).limits.first?.windows.first?.percent == 36)
    }

    @Test func windowNames() {
        #expect(CodexResolver.windowName(300) == "5시간")
        #expect(CodexResolver.windowName(10080) == "주간")
        #expect(CodexResolver.windowName(1440) == "1일")
        #expect(CodexResolver.windowName(90) == "90분")
        #expect(CodexResolver.planLabel("prolite") == "Pro Lite")
    }
}
