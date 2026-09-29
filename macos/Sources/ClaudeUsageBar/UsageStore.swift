import Foundation
import Observation
import UsageCore

@MainActor
@Observable
final class UsageStore {
    private(set) var display = DisplayState()
    private(set) var tokens = TokenTally()
    private(set) var codex: CodexDisplay?
    private(set) var isRefreshing = false
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

    static func live(settings: AppSettings) -> UsageStore {
        let env = ProcessInfo.processInfo.environment
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
            stateURL: AppLog.dataDir.appendingPathComponent("state.json"),
            log: { AppLog.write($0) })
        return UsageStore(engine: engine, settings: settings, alertURL: AppLog.dataDir.appendingPathComponent("alerts.json"))
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

    func refresh(force: Bool) async {
        if force { isRefreshing = true }
        let out = await engine.tick(force: force, interval: settings.interval)
        display = out.display
        tokens = out.tokens
        codex = out.codex
        isRefreshing = false
        evaluateAlerts()
        onChange?()
    }

    private func evaluateAlerts() {
        let before = alertState
        var events = alertState.evaluate(display, now: Date(), settings: settings.alerts)
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
