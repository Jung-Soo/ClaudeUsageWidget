import AppKit
import SwiftUI
import UsageCore

/// `ClaudeUsageBar --snapshot <폴더>`: 실제 데이터로 패널·설정·메뉴바 항목(①~④)을 PNG로 그리고 끝낸다(검증·문서용).
/// `<폴더>/docs/`에는 문서용 다크 이미지(카드 모양, 메뉴바+패널 합성)를 만든다. 언어는 `CUB_LANG=en|ko`로 고른다.
@MainActor
enum Snapshot {
    static func run(to dir: URL) async {
        // 사용자의 설정을 바꾸지 않도록 임시 저장소를 쓴다
        let settings = AppSettings(defaults: UserDefaults(suiteName: "snapshot-\(UUID().uuidString)")!)
        settings.showClaude = true
        settings.showCodex = true
        let store = UsageStore.live(settings: settings, offline: true)   // 실행 중인 앱과 상태 파일·API를 공유하지 않는다
        await store.refresh(force: false)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            let bg = scheme == .light ? Color.white : Color(white: 0.16)
            save(PanelView(store: store).background(bg).environment(\.colorScheme, scheme), dir.appendingPathComponent("panel-\(name).png"))
            let items = VStack(alignment: .leading, spacing: 6) {
                ForEach(MenubarStyle.allCases) { style in
                    HStack(spacing: 10) {
                        Text(style.label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                        HStack(spacing: 4) {
                            StatusItemController.imageView(store.display, style: style)
                            let t = StatusItemController.titleText(store.display, style: style)
                            if !t.isEmpty { Text(t).font(.system(size: 13).monospacedDigit()) }
                        }
                        .frame(height: 24)
                    }
                }
            }
            save(items.padding(10).background(bg).environment(\.colorScheme, scheme), dir.appendingPathComponent("menubar-\(name).png"))
            let seg = HStack(spacing: 12) {
                ForEach(Array(StatusItemController.segments(store, style: .donutNumbers).enumerated()), id: \.offset) { _, sg in
                    HStack(spacing: 4) {
                        sg.image
                        if !sg.text.isEmpty { Text(sg.text).font(.system(size: 13).monospacedDigit()) }
                    }
                }
            }
            .frame(height: 24)
            save(seg.padding(8).background(bg).environment(\.colorScheme, scheme), dir.appendingPathComponent("menubar-combined-\(name).png"))
            settings.compactPanel = true
            save(PanelView(store: store).background(bg).environment(\.colorScheme, scheme), dir.appendingPathComponent("panel-compact-\(name).png"))
            settings.compactPanel = false
            if scheme == .light {
                settings.showCodex = false
                save(PanelView(store: store).background(bg).environment(\.colorScheme, scheme), dir.appendingPathComponent("panel-claude-only.png"))
                settings.showCodex = true
                settings.showClaude = false
                save(PanelView(store: store).background(bg).environment(\.colorScheme, scheme), dir.appendingPathComponent("panel-codex-only.png"))
                settings.showClaude = true
            }
        }
        var settingsDark: NSImage?
        for scheme in [NSAppearance.Name.aqua, .darkAqua] {
            let img = saveViaWindow(SettingsView(settings: settings, onTestAlert: {}), appearance: scheme,
                                    dir.appendingPathComponent("settings-\(scheme == .aqua ? "light" : "dark").png"))
            if scheme == .darkAqua { settingsDark = img }
        }
        // 문서용: 고정 예시 값, 언어는 실행 환경(CUB_LANG)을 따른다
        let demoSettings = AppSettings(defaults: UserDefaults(suiteName: "snapshot-demo-\(UUID().uuidString)")!)
        demoSettings.showClaude = true
        demoSettings.showCodex = true
        let demo = UsageStore.live(settings: demoSettings, offline: true)
        demo.loadDemo()
        let plist = URL(fileURLWithPath: "Resources/Info.plist")
        let version = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? "dev"
        let demoSettingsImage = saveViaWindow(SettingsView(settings: demoSettings, onTestAlert: {}, version: version), appearance: .darkAqua,
                                              FileManager.default.temporaryDirectory.appendingPathComponent("cub-settings.png"))
        _ = settingsDark
        docs(store: demo, settings: demoSettings, settingsImage: demoSettingsImage, to: dir.appendingPathComponent("docs"))
        print("snapshots → \(dir.path)")
    }

    // MARK: - 문서용 다크 이미지

    private static let canvas = LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.20), Color(red: 0.06, green: 0.06, blue: 0.09)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let cardFill = Color(red: 0.16, green: 0.16, blue: 0.17)

    /// 패널처럼 둥근 카드
    private static func card(_ content: some View) -> some View {
        content
            .background(cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private static func onCanvas(_ content: some View, padding: CGFloat = 28) -> some View {
        content.padding(padding).background(canvas).environment(\.colorScheme, .dark)
    }

    private static func segmentsRow(_ store: UsageStore, style: MenubarStyle = .donutNumbers) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(StatusItemController.segments(store, style: style).enumerated()), id: \.offset) { _, sg in
                HStack(spacing: 5) {
                    sg.image
                    if !sg.text.isEmpty { Text(sg.text).font(.system(size: 13).monospacedDigit()) }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private static func docs(store: UsageStore, settings: AppSettings, settingsImage: NSImage?, to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suffix = Lang.current == .ko ? "-ko" : ""
        func url(_ name: String) -> URL { dir.appendingPathComponent("\(name)\(suffix).png") }

        // 메뉴바 + 펼친 패널
        let hero = VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 16) {
                Spacer()
                segmentsRow(store)
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("9:41").font(.system(size: 13, weight: .medium)).monospacedDigit()
            }
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Color.black.opacity(0.35))
            card(PanelView(store: store, forImage: true)).padding(.trailing, 70).padding(.bottom, 36)
        }
        .frame(width: 470)
        .background(canvas)
        .environment(\.colorScheme, .dark)
        save(hero, url("hero"))

        save(onCanvas(card(PanelView(store: store, forImage: true))), url("panel"))
        settings.compactPanel = true
        save(onCanvas(card(PanelView(store: store, forImage: true))), url("panel-compact"))
        settings.compactPanel = false

        save(onCanvas(segmentsRow(store).padding(.horizontal, 14).frame(height: 30)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8)), padding: 20),
             url("menubar"))

        let styles = VStack(alignment: .leading, spacing: 8) {
            ForEach(MenubarStyle.allCases) { style in
                HStack(spacing: 12) {
                    Text(style.label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                    segmentsRow(store, style: style).frame(height: 24)
                }
            }
        }
        save(onCanvas(card(styles.padding(16))), url("menubar-styles"))

        if let settingsImage {
            save(onCanvas(card(Image(nsImage: settingsImage).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))),
                 url("settings"))
        }
    }

    /// AppKit이 그리는 컨트롤(Form 등)은 ImageRenderer로 안 그려져서, 화면 밖 창에 띄운 뒤 뜬다.
    @discardableResult
    private static func saveViaWindow(_ view: some View, appearance: NSAppearance.Name, _ url: URL) -> NSImage? {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let w = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: appearance)
        w.backgroundColor = appearance == .aqua ? .windowBackgroundColor : NSColor(white: 0.16, alpha: 1)
        w.contentView = host
        w.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        defer { w.orderOut(nil) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        let img = NSImage(size: host.bounds.size)
        img.addRepresentation(rep)
        return img
    }

    private static func save(_ view: some View, _ url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
