import AppKit
import SwiftUI
import UsageCore

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var store: UsageStore? = nil
    var onTestAlert: () -> Void
    var version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    @State private var loginOn = false
    @State private var loginError: String?

    private static let presets: [(Double, Double)] = [(80, 95), (85, 95), (90, 98)]

    var body: some View {
        Form {
            Section {
                Toggle("Claude", isOn: $settings.showClaude).disabled(settings.showClaude && !settings.showCodex)
                Toggle("Codex", isOn: $settings.showCodex).disabled(settings.showCodex && !settings.showClaude)
            } header: {
                Text(L("표시할 서비스", "Services"))
            } footer: {
                Text(L("쓰지 않는 서비스는 끄세요. Claude를 끄면 키체인·사용량 API에 접근하지 않습니다.",
                       "Turn off what you don't use. With Claude off, the app never touches the Keychain or the usage API."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("CLI 토큰 자동 갱신", "Auto-refresh CLI token"), isOn: $settings.autoRefreshClaudeToken)
                    .disabled(!settings.showClaude)
                if let last = store?.lastRefresh {
                    LabeledContent(L("마지막 자동 갱신", "Last auto refresh"), value: RefreshText.describe(last))
                }
            } header: {
                Text("Claude")
            } footer: {
                Text(L("CLI 토큰이 만료되면(약 8시간마다) 앱이 claude를 짧게 한 번 실행해 CLI가 스스로 토큰을 갱신하게 합니다. 갱신마다 약 500토큰을 씁니다. 끄면 데스크톱 앱 기록이나 마지막 값으로 보여 줍니다.",
                       "When the CLI token expires (about every 8 hours), the app runs claude once, briefly, so the CLI refreshes its own token. About 500 tokens per refresh. When off, the panel falls back to desktop app data or the last value."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("일반", "General")) {
                Picker(L("메뉴바 표시", "Menu bar"), selection: $settings.menubarStyle) {
                    ForEach(MenubarStyle.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("패널 크기", "Panel"), selection: $settings.compactPanel) {
                    Text(L("기본 (도넛)", "Standard (donuts)")).tag(false)
                    Text(L("작게 (가로 막대)", "Compact (bars)")).tag(true)
                }
                Picker(L("Claude 한도 조회 주기", "Claude limit check"), selection: $settings.interval) {
                    ForEach([120.0, 180, 300, 600], id: \.self) { Text(L("\(Int($0 / 60))분", "Every \(Int($0 / 60)) min")).tag($0) }
                }
                .disabled(!settings.showClaude)
                Picker(L("언어", "Language"), selection: Binding(get: { settings.language }, set: { v in
                    settings.language = v
                    Relauncher.relaunchIfNeeded(for: v)
                })) {
                    Text(L("시스템 설정", "System")).tag("")
                    Text("English").tag("en")
                    Text("한국어").tag("ko")
                }
                Toggle(L("로그인 시 자동 실행", "Launch at login"), isOn: Binding(get: { loginOn }, set: { on in
                    loginError = settings.setLaunchAtLogin(on)
                    loginOn = settings.launchAtLogin
                }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section(L("알림", "Notifications")) {
                Toggle(L("알림 켜기", "Enable notifications"), isOn: $settings.alerts.enabled)
                Picker(L("기준치", "Thresholds"), selection: Binding(
                    get: { "\(Int(settings.alerts.warnPct))/\(Int(settings.alerts.dangerPct))" },
                    set: { v in
                        let p = v.split(separator: "/").compactMap { Double($0) }
                        if p.count == 2 { settings.alerts.warnPct = p[0]; settings.alerts.dangerPct = p[1] }
                    })) {
                    ForEach(Self.presets, id: \.0) {
                        Text(L("경고 \(Int($0.0))% · 위험 \(Int($0.1))%", "Warn \(Int($0.0))% · danger \(Int($0.1))%"))
                            .tag("\(Int($0.0))/\(Int($0.1))")
                    }
                }
                .disabled(!settings.alerts.enabled)
                Toggle(L("사용 속도 예측 알림", "Pace forecast"), isOn: $settings.alerts.pace).disabled(!settings.alerts.enabled)
                Toggle(L("추가 크레딧 사용 알림", "Extra credit usage"), isOn: $settings.alerts.credit).disabled(!settings.alerts.enabled)
                Button(L("알림 테스트", "Send Test Notification"), action: onTestAlert)
            }
            Section(L("정보", "About")) {
                LabeledContent(L("버전", "Version"), value: version)
                HStack {
                    Button(L("데이터 폴더 열기", "Open Data Folder")) { NSWorkspace.shared.open(AppLog.dataDir) }
                    Button(L("로그 열기", "Open Log")) { NSWorkspace.shared.open(AppLog.url) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginOn = settings.launchAtLogin }
    }
}

/// 언어는 시작할 때 정해지므로(`Lang.current`), 바꾸면 앱을 다시 띄운다.
enum Relauncher {
    @MainActor
    static func relaunchIfNeeded(for language: String) {
        let next = Lang(rawValue: language)
            ?? ((Locale.preferredLanguages.first ?? "en").hasPrefix("ko") ? .ko : .en)
        let bundle = Bundle.main.bundlePath
        guard next != Lang.current, bundle.hasSuffix(".app") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", bundle]   // 단일 인스턴스 검사에 걸리지 않게 종료 뒤에 연다
        try? p.run()
        NSApp.terminate(nil)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let store: UsageStore?
    private let onTestAlert: () -> Void

    init(settings: AppSettings, store: UsageStore? = nil, onTestAlert: @escaping () -> Void) {
        self.settings = settings
        self.store = store
        self.onTestAlert = onTestAlert
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, store: store, onTestAlert: onTestAlert))
            host.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: host)
            w.title = L("Claude Usage Bar 설정", "Claude Usage Bar Settings")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
