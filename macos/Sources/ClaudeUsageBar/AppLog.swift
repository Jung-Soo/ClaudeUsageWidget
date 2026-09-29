import Foundation
import UsageCore

/// `~/Library/Application Support/ClaudeUsageBar/app.log` (최근 200줄, 토큰 마스킹).
enum AppLog {
    static let dataDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeUsageBar")
    static let url = dataDir.appendingPathComponent("app.log")
    private static let queue = DispatchQueue(label: "ClaudeUsageBar.log")

    static func write(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        let stamp = f.string(from: Date())
        let entry = "\(stamp) \(Redact.secrets(line))"
        queue.async {
            try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            var lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
            lines.append(entry)
            if lines.count > 200 { lines.removeFirst(lines.count - 200) }
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
