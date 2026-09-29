import Foundation
@testable import UsageCore

enum Fx {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    }
    static func data(_ name: String) -> Data { try! Data(contentsOf: url(name)) }
}

let seoul: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
}()

func date(_ iso: String) -> Date { ISODate.parse(iso)! }

struct StubCredentials: CredentialProvider {
    var cred: OAuthCredential?
    func load() throws -> OAuthCredential? { cred }
}

final class StubAPI: UsageFetching, @unchecked Sendable {
    var result: Result<UsageSnapshot, UsageAPIError>
    private(set) var calls = 0
    init(_ r: Result<UsageSnapshot, UsageAPIError>) { result = r }
    func fetch(token: String, now: Date) async throws -> UsageSnapshot {
        calls += 1
        switch result {
        case .success(var s): s.fetchedAt = now; return s
        case .failure(let e): throw e
        }
    }
}

struct StubDesktop: DesktopHistoryReading {
    var list: [DesktopSample]
    func samples() -> [DesktopSample] { list }
}

final class MutableClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}
