import Foundation
import Testing
@testable import UsageCore

@Suite struct SessionLogScannerTests {
    /// 픽스처: 어제 메시지 1건, 오늘 msg_A 2번(중복), user 줄, 오늘 msg_B.
    func makeRoot() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("-Users-me-proj")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s.jsonl")
        try Fx.data("session-sample.jsonl").write(to: file)
        return (root, file)
    }

    let now = date("2026-09-29T03:00:00Z")   // 12:00 KST

    @Test func countsTodayOnceEach() throws {
        let (root, _) = try makeRoot()
        let t = SessionLogScanner(root: root, calendar: seoul).scan(now: now)
        #expect(t.messages == 2)
        #expect(t.input == 12)
        #expect(t.output == 445)
        #expect(t.cacheWrite == 24002)
        #expect(t.cacheRead == 43954)
    }

    @Test func readsOnlyNewCompleteLines() throws {
        let (root, file) = try makeRoot()
        let s = SessionLogScanner(root: root, calendar: seoul)
        _ = s.scan(now: now)

        let c = #"{"type":"assistant","timestamp":"2026-09-29T02:30:00.000Z","requestId":"req_C","message":{"id":"msg_C","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        let h = try FileHandle(forWritingTo: file)
        h.seekToEndOfFile()
        h.write(Data((c + "\n").utf8))
        h.write(Data(#"{"type":"assistant","timestamp":"2026-09-29T02:31"#.utf8))   // 아직 쓰는 중인 줄
        try h.close()

        let t = s.scan(now: now)
        #expect(t.messages == 3)
        #expect(t.output == 446)
    }

    @Test func resetsAtMidnight() throws {
        let (root, _) = try makeRoot()
        let s = SessionLogScanner(root: root, calendar: seoul)
        #expect(s.scan(now: now).messages == 2)
        #expect(s.scan(now: date("2026-09-29T16:00:00Z")).messages == 0)   // 9/30 01:00 KST
    }
}

@Suite struct DesktopHistoryTests {
    @Test func parsesFixture() {
        let r = DesktopHistoryReader(url: Fx.url("plan-usage-history-sample.json"))
        let s = r.samples()
        #expect(s.count == 8)
        #expect(r.latest()?.fiveHour == 2)
        #expect(r.latest()?.weekly == 25)
        #expect(s.contains { $0.extra == 9.78 })
    }

    @Test func ignoresUnknownVersion() {
        #expect(DesktopHistoryReader.parse(Data(#"{"version":3,"samples":[{"t":1,"u":{"fh":1}}]}"#.utf8)).isEmpty)
    }
}
