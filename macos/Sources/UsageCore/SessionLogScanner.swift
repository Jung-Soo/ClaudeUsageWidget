import Foundation

/// `~/.claude/projects/**/*.jsonl`에서 오늘 assistant 메시지의 토큰을 증분 집계한다.
/// - 파일별로 읽은 위치를 기억해 새 줄만 읽고, 완성된 줄(개행으로 끝난 줄)까지만 소비한다
/// - 같은 메시지가 content block마다 중복 기록되므로 `message.id|requestId`로 한 번만 센다
/// - 자정이 지나면 처음부터 다시 센다
public final class SessionLogScanner {
    public let root: URL
    private let calendar: Calendar
    private var day: Date?
    private var offsets: [String: UInt64] = [:]
    private var seen = Set<String>()
    private var tally = TokenTally()
    /// 폴더 전체 탐색은 60초에 한 번. 그 사이에는 오늘 수정된 파일 목록만 다시 확인한다.
    private var candidates: [URL] = []
    private var enumeratedAt = Date.distantPast
    private let iso = ISO8601DateFormatter()
    private static let marker = Data(#""type":"assistant""#.utf8)
    private static let chunk = 4 << 20

    public init(root: URL, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func scan(now: Date) -> TokenTally {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return tally }
        if day != start {
            day = start
            offsets = [:]
            seen = []
            tally = TokenTally()
            enumeratedAt = .distantPast
        }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        if now.timeIntervalSince(enumeratedAt) >= 60 || now < enumeratedAt {
            enumeratedAt = now
            candidates = []
            if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) {
                for case let url as URL in en where url.pathExtension == "jsonl" {
                    if let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       mod >= start { candidates.append(url) }
                }
            }
        }
        for url in candidates {
            // URL은 리소스 값을 캐시하므로 크기는 매번 stat으로 읽는다
            var st = stat()
            guard stat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            let size = UInt64(st.st_size)
            var pos = offsets[url.path] ?? 0
            if size < pos { pos = 0 }            // 파일이 새로 써졌음. 중복 제거 집합이 이중 집계를 막는다
            if size == pos { continue }
            offsets[url.path] = read(url, from: pos, start: start, end: end)
        }
        return tally
    }

    /// 새로 소비한 위치를 돌려준다.
    private func read(_ url: URL, from pos: UInt64, start: Date, end: Date) -> UInt64 {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return pos }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: pos) } catch { return pos }
        var consumed = pos
        var carry = Data()
        while true {
            guard let data = try? fh.read(upToCount: Self.chunk), !data.isEmpty else { break }
            carry.append(data)
            guard let lastNL = carry.lastIndex(of: 0x0A) else { continue }
            let complete = carry[carry.startIndex...lastNL]
            autoreleasepool {   // JSONSerialization이 만드는 임시 객체를 청크마다 비운다
                for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                    handle(Data(line), start: start, end: end)
                }
            }
            consumed += UInt64(complete.count)
            carry = Data(carry[carry.index(after: lastNL)...])
        }
        return consumed
    }

    private func handle(_ line: Data, start: Date, end: Date) {
        guard line.range(of: Self.marker) != nil,
              let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              j["type"] as? String == "assistant",
              let m = j["message"] as? [String: Any],
              let u = m["usage"] as? [String: Any],
              let tsRaw = j["timestamp"] as? String,
              let ts = iso.date(from: tsRaw) ?? ISODate.parse(tsRaw),
              ts >= start, ts < end else { return }
        if let id = m["id"] as? String {
            let key = id + "|" + (j["requestId"] as? String ?? "")
            guard seen.insert(key).inserted else { return }
        }
        func n(_ k: String) -> Int64 { (u[k] as? NSNumber)?.int64Value ?? 0 }
        tally.input += n("input_tokens")
        tally.output += n("output_tokens")
        tally.cacheWrite += n("cache_creation_input_tokens")
        tally.cacheRead += n("cache_read_input_tokens")
        tally.messages += 1
    }
}
