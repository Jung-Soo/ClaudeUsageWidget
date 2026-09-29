import Foundation
import Observation
import UsageCore

@MainActor
@Observable
final class UsageStore {
    private(set) var display = DisplayState()
    private(set) var tokens = TokenTally()
    private(set) var codex: CodexDisplay?
    private(set) var codexTokens: CodexTokenTally?
    /// 수동 갱신 표시. 겹친 틱이 먼저 끝나도 꺼지지 않도록 진행 중인 수동 갱신 수로 판단한다.
    private var forcedInFlight = 0
    private var ticking = 0
    var isRefreshing: Bool { forcedInFlight > 0 }
    var onChange: (() -> Void)?
    var onAlerts: (([AlertEvent]) -> Void)?

    let settings: AppSettings
    private let engine: UsageEngine
    private var alertState: AlertState
    private let alertURL: URL?
    private var loop: Task<Void, Never>?

    init(engine: UsageEngine, settings: AppSettings, alertURL: URL?) {
        self.engine = engine
        self.settings = settings
        self.alertURL = alertURL
        alertState = alertURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(AlertState.self, from: $0) } ?? AlertState()
    }

    /// offline: 스냅샷 모드용. 실제 state.json의 복사본으로 시작하고, API를 부르지 않고, 알림 기록을 쓰지 않는다.
    static func live(settings: AppSettings, offline: Bool = false) -> UsageStore {
        let env = ProcessInfo.processInfo.environment
        var stateURL = AppLog.dataDir.appendingPathComponent("state.json")
        if offline {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("cub-snapshot-\(UUID().uuidString).json")
            try? FileManager.default.copyItem(at: stateURL, to: copy)
            stateURL = copy
        }
        let configDir = env["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let engine = UsageEngine(
            credentials: ChainCredentialProvider.standard(configDir: configDir),
            api: UsageAPIClient(),
            desktop: DesktopHistoryReader(),
            projectsRoot: configDir.appendingPathComponent("projects"),
            codexSessionsRoot: (env["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
                .appendingPathComponent("sessions"),
            stateURL: stateURL,
            allowNetwork: !offline,
            log: { if !offline { AppLog.write($0) } })
        return UsageStore(engine: engine, settings: settings,
                          alertURL: offline ? nil : AppLog.dataDir.appendingPathComponent("alerts.json"))
    }

    /// 10초마다: 로컬 토큰 집계 + (주기가 됐으면) API.
    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(force: false)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// 수동 갱신이 아니면, 이미 진행 중인 틱이 있을 때 건너뛴다(주기 틱·패널 열기·설정 변경이 겹치는 경우).
    func refresh(force: Bool) async {
        if !force && ticking > 0 { return }
        ticking += 1
        if force { forcedInFlight += 1 }
        defer {
            ticking -= 1
            if force { forcedInFlight -= 1 }
        }
        let out = await engine.tick(force: force, interval: settings.interval,
                                    claude: settings.showClaude, codex: settings.showCodex)
        display = out.display
        tokens = out.tokens
        codex = out.codex
        codexTokens = out.codexTokens
        evaluateAlerts()
        onChange?()
    }

    private func evaluateAlerts() {
        let before = alertState
        var events = settings.showClaude ? alertState.evaluate(display, now: Date(), settings: settings.alerts) : []
        if settings.showCodex, let c = codex {
            // 같은 규칙으로 평가하되, 알림 제목에 "Codex"를 붙이고 멈춘 값이면 건너뛴다
            var d = DisplayState()
            d.rows = c.rows.map { var r = $0; r.name = "Codex " + r.name; return r }
            d.asOf = c.asOf
            d.source = .api
            if c.isStale { d.staleRowIDs = Set(d.rows.map(\.id)) }
            events += alertState.evaluate(d, now: Date(), settings: settings.alerts)
        }
        if alertState != before, let alertURL, let data = try? JSONEncoder().encode(alertState) {
            try? data.write(to: alertURL, options: .atomic)
        }
        if !events.isEmpty { onAlerts?(events) }
    }
}
