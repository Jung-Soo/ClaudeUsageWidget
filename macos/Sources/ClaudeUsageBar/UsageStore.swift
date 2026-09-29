import Foundation
import Observation
import UsageCore

@MainActor
@Observable
final class UsageStore {
    private(set) var display = DisplayState()
    private(set) var tokens = TokenTally()
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
        isRefreshing = false
        evaluateAlerts()
        onChange?()
    }

    private func evaluateAlerts() {
        let before = alertState
        let events = alertState.evaluate(display, now: Date(), settings: settings.alerts)
        if alertState != before, let alertURL, let data = try? JSONEncoder().encode(alertState) {
            try? data.write(to: alertURL, options: .atomic)
        }
        if !events.isEmpty { onAlerts?(events) }
    }
}
