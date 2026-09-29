import Foundation
import Observation
import ServiceManagement
import UsageCore

enum MenubarStyle: Int, CaseIterable, Identifiable {
    case donut = 1          // ① 도넛만
    case donutActive = 2    // ② 도넛 + 숫자
    case threeDonuts = 3    // ③ 미니 도넛 3개
    case donutNumbers = 4   // ④ 도넛 + 숫자 3개

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .donut: "① 도넛만"
        case .donutActive: "② 도넛 + 숫자"
        case .threeDonuts: "③ 미니 도넛 3개"
        case .donutNumbers: "④ 도넛 + 숫자 3개"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var interval: TimeInterval { didSet { defaults.set(interval, forKey: "apiInterval") } }
    var menubarStyle: MenubarStyle { didSet { defaults.set(menubarStyle.rawValue, forKey: "menubarStyle") } }
    var alerts: AlertSettings {
        didSet { if let d = try? JSONEncoder().encode(alerts) { defaults.set(d, forKey: "alerts") } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let i = defaults.double(forKey: "apiInterval")
        interval = FetchPolicy.clamp(i > 0 ? i : 180)
        menubarStyle = MenubarStyle(rawValue: defaults.integer(forKey: "menubarStyle")) ?? .donutNumbers
        alerts = defaults.data(forKey: "alerts").flatMap { try? JSONDecoder().decode(AlertSettings.self, from: $0) } ?? AlertSettings()
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// 실패하면 이유를 돌려준다.
    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            AppLog.write("[login-item] \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
