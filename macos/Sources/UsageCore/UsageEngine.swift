import Foundation

/// 앱을 다시 켜도 이어받는 상태.
struct PersistedState: Codable {
    var policy = FetchPolicy()
    var status: FetchStatus = .idle
    var lastAPI: UsageSnapshot?
    var plan: String?
}

public struct EngineOutput: Sendable, Equatable {
    public var display: DisplayState
    public var tokens: TokenTally
    public var calledAPI: Bool
    public var codex: CodexDisplay?
    public var codexTokens: CodexTokenTally?
}

public actor UsageEngine {
    private let credentials: any CredentialProvider
    private let api: any UsageFetching
    private let desktop: any DesktopHistoryReading
    private let scanner: SessionLogScanner
    private let codexReader: CodexLogReader?
    private let codexTokenScanner: CodexTokenScanner?
    /// Codex 값은 Codex를 쓸 때만 바뀌므로 30초에 한 번만 읽는다.
    private var codexSnapshot = CodexSnapshot()
    private var codexReadAt = Date.distantPast
    /// 첫 스캔(오늘 로그 전체, 수백 MB일 수 있음) 뒤에 해제된 메모리를 바로 시스템에 돌려준다.
    private var relievedAfterFirstScan = false
    private let stateURL: URL?
    private let clock: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private var state: PersistedState

    public init(credentials: any CredentialProvider,
                api: any UsageFetching,
                desktop: any DesktopHistoryReading,
                projectsRoot: URL,
                codexSessionsRoot: URL? = nil,
                stateURL: URL?,
                calendar: Calendar = .current,
                clock: @escaping @Sendable () -> Date = { Date() },
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.credentials = credentials
        self.api = api
        self.desktop = desktop
        self.scanner = SessionLogScanner(root: projectsRoot, calendar: calendar)
        self.codexReader = codexSessionsRoot.map { CodexLogReader(root: $0, calendar: calendar) }
        self.codexTokenScanner = codexSessionsRoot.map { CodexTokenScanner(root: $0, calendar: calendar) }
        self.stateURL = stateURL
        self.clock = clock
        self.log = log
        if let stateURL, let data = try? Data(contentsOf: stateURL),
           let s = try? JSONDecoder().decode(PersistedState.self, from: data) {
            state = s
        } else {
            state = PersistedState()
        }
    }

    /// - claude: 끄면 키체인·API·Claude 로그를 전혀 건드리지 않는다
    /// - codex: 끄면 Codex 로그를 읽지 않는다
    public func tick(force: Bool, interval: TimeInterval, claude: Bool = true, codex: Bool = true) async -> EngineOutput {
        let now = clock()
        var tokens = TokenTally()
        var called = false
        if claude {
            tokens = scanner.scan(now: now)
            if state.policy.shouldCall(now: now, force: force) {
                state.policy.willCall(now: now, force: force, interval: interval)
                called = await callAPI(now: now, interval: interval)
                save()
            }
        }

        let later = clock()
        var display = DisplayState()
        if claude {
            display = DisplayResolver.resolve(api: state.lastAPI, desktop: desktop.latest(), status: state.status,
                                              plan: state.plan, now: later, interval: interval)
        }
        var codexDisplay: CodexDisplay?
        var codexTokens: CodexTokenTally?
        if codex, let codexReader {
            if force || later.timeIntervalSince(codexReadAt) >= 30 {
                codexSnapshot = codexReader.read(now: later)
                codexReadAt = later
            }
            codexDisplay = CodexResolver.resolve(codexSnapshot, now: later)
            codexTokens = codexTokenScanner?.scan(now: later)
        }
        if !relievedAfterFirstScan {
            relievedAfterFirstScan = true
            malloc_zone_pressure_relief(nil, 0)
        }
        return EngineOutput(display: display, tokens: tokens, calledAPI: called, codex: codexDisplay, codexTokens: codexTokens)
    }

    /// 실제로 네트워크 호출을 했으면 true.
    private func callAPI(now: Date, interval: TimeInterval) async -> Bool {
        let cred: OAuthCredential?
        do { cred = try credentials.load() } catch {
            state.status = .error("credentials: \(error.localizedDescription)")
            state.policy.failed(now: now, interval: interval)
            log("[credentials] \(error.localizedDescription)")
            return false
        }
        guard let cred else {
            state.status = .noCredential
            state.policy.credentialUnavailable(now: now)
            return false
        }
        state.plan = cred.planLabel ?? state.plan
        if cred.isExpired(at: now) {
            if state.status != .tokenExpired { log("[token] CLI access token expired; waiting for Claude Code to refresh it") }
            state.status = .tokenExpired
            state.policy.credentialUnavailable(now: now)
            return false
        }

        do {
            let snap = try await api.fetch(token: cred.accessToken, now: now)
            state.lastAPI = snap
            state.status = .ok
            state.policy.succeeded(now: now, interval: interval)
        } catch let e as UsageAPIError {
            switch e {
            case .rateLimited(let ra):
                state.policy.hitRateLimit(now: now, retryAfter: ra)
                state.status = .rateLimited(until: state.policy.nextAPI)
                log("[usage] 429, next try \(state.policy.nextAPI)")
            case .unauthorized(let code):
                state.status = .auth
                state.policy.failed(now: now, interval: interval)
                log("[usage] HTTP \(code)")
            case .http(let code, let body):
                state.status = .error("HTTP \(code)")
                state.policy.failed(now: now, interval: interval)
                log("[usage] HTTP \(code) \(body)")
            case .decoding(let m):
                state.status = .error("응답 형식 변경")
                state.policy.failed(now: now, interval: interval)
                log("[usage] decoding \(m)")
            case .network(let m):
                state.status = .error("네트워크")
                state.policy.failed(now: now, interval: interval)
                log("[usage] network \(m)")
            }
        } catch {
            state.status = .error(error.localizedDescription)
            state.policy.failed(now: now, interval: interval)
        }
        return true
    }

    private func save() {
        guard let stateURL, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }
}
