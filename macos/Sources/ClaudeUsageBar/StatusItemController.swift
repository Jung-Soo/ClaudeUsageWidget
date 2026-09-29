import AppKit
import SwiftUI
import UsageCore

/// 메뉴바 항목. 형식은 설정(①~④)을 따르고 기본은 ④ 도넛 + 숫자 3개(5시간 · 주간 · 모델별 최고치).
/// ③·④가 노치 뒤로 가려지면 ②로 줄이고, 10분마다·화면 구성이 바뀔 때 다시 넓혀 본다.
/// Codex 기록이 있고 설정이 켜져 있으면 왼쪽에 Codex 항목(도넛 + 가장 높은 %)을 따로 둔다. 어느 항목을 눌러도 같은 패널이 열린다.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let openSettings: () -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var codexItem: NSStatusItem?
    private let popover = NSPopover()
    private var compact = false
    /// 시작 직후 창이 뜨기 전에도 '안 보임' 알림이 와서, 한 번 보인 뒤부터만 판단한다.
    private var hasBeenVisible = false
    private var lastExpandTry = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    init(store: UsageStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettings = openSettings
        super.init()

        let host = NSHostingController(rootView: PanelView(
            store: store,
            onOpenSettings: { [weak self] in self?.popover.performClose(nil); openSettings() },
            onOpenData: { NSWorkspace.shared.open(AppLog.dataDir) },
            onQuit: { NSApp.terminate(nil) }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient

        if let b = item.button {
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        render()

        let nc = NotificationCenter.default
        if let w = item.button?.window {
            observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.occlusionChanged() }
            })
        }
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tryExpand() }
        })
    }

    var effectiveStyle: MenubarStyle {
        let s = store.settings.menubarStyle
        return compact && s.rawValue >= MenubarStyle.threeDonuts.rawValue ? .donutActive : s
    }

    func render() {
        guard let b = item.button else { return }
        let d = store.display
        let style = effectiveStyle
        b.image = Self.image(d, style: style, scale: NSScreen.main?.backingScaleFactor ?? 2)
        let title = Self.titleText(d, style: style)
        b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        b.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " " + title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .baselineOffset: 0.5,
        ])
        b.toolTip = tooltip(d)
        renderCodex()

        if compact, Date().timeIntervalSince(lastExpandTry) > 600 { tryExpand() }
    }

    private func renderCodex() {
        let settings = store.settings
        guard settings.showCodex, let c = store.codex, c.active != nil else {
            if let codexItem { NSStatusBar.system.removeStatusItem(codexItem); self.codexItem = nil }
            return
        }
        if codexItem == nil {
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            it.button?.target = self
            it.button?.action = #selector(clicked(_:))
            it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            codexItem = it
        }
        guard let b = codexItem?.button else { return }
        b.image = Self.codexImage(c, scale: NSScreen.main?.backingScaleFactor ?? 2)
        let title = Self.codexTitle(c, style: settings.menubarStyle)
        b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        b.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " " + title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .baselineOffset: 0.5,
        ])
        b.toolTip = (["Codex"] + c.rows.map { "\($0.name) \(Format.percent($0.percent))%" }).joined(separator: " · ")
            + (c.isStale ? " · \(Format.ago(c.asOf, now: Date())) 값" : "")
    }

    static func codexTitle(_ c: CodexDisplay, style: MenubarStyle) -> String {
        guard let a = c.active, style != .donut, style != .threeDonuts else { return "" }
        return Format.percent(a.percent)
    }

    static func codexImageView(_ c: CodexDisplay) -> some View {
        let a = c.active
        return Donut(percent: a?.percent ?? 0, color: a.map { Palette.color(for: $0, stale: c.isStale) } ?? Palette.stale,
                     lineWidth: 2.6).frame(width: 15, height: 15)
    }

    static func codexImage(_ c: CodexDisplay, scale: CGFloat) -> NSImage? {
        let r = ImageRenderer(content: codexImageView(c))
        r.scale = scale
        let img = r.nsImage
        img?.isTemplate = false
        return img
    }

    func showPanel() {
        guard let b = item.button else { return }
        showPanel(from: b)
    }

    private func showPanel(from b: NSStatusBarButton) {
        guard !popover.isShown else { return }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await store.refresh(force: false) }
    }

    private func tooltip(_ d: DisplayState) -> String {
        var parts = d.rows.map { "\($0.name) \(Format.percent($0.percent))%" }
        if parts.isEmpty { parts = ["Claude 사용량"] }
        if d.source == .desktopHistory { parts.append("데스크톱 앱 기록") }
        return parts.joined(separator: " · ")
    }

    // MARK: - 그리기 (스냅샷 모드도 같은 함수를 쓴다)

    static func titleText(_ d: DisplayState, style: MenubarStyle) -> String {
        guard let a = d.active else { return style == .donut || style == .threeDonuts ? "" : "–" }
        switch style {
        case .donut, .threeDonuts: return ""
        case .donutActive: return "\(Format.percent(a.percent))%"
        case .donutNumbers:
            return [d.fiveHour?.percent, d.weekly?.percent, d.models.first?.percent]
                .compactMap { $0 }.map(Format.percent).joined(separator: " · ")
        }
    }

    static func imageView(_ d: DisplayState, style: MenubarStyle) -> AnyView {
        func color(_ r: LimitRow?) -> Color { r.map { Palette.color(for: $0, stale: d.isStale($0)) } ?? Palette.stale }
        if style == .threeDonuts {
            let rows: [LimitRow?] = [d.fiveHour, d.weekly, d.models.first]
            return AnyView(HStack(spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    Donut(percent: r?.percent ?? 0, color: color(r), lineWidth: 2.4).frame(width: 13, height: 13)
                }
            })
        }
        return AnyView(Donut(percent: d.active?.percent ?? 0, color: color(d.active), lineWidth: 2.6).frame(width: 15, height: 15))
    }

    static func image(_ d: DisplayState, style: MenubarStyle, scale: CGFloat) -> NSImage? {
        let r = ImageRenderer(content: imageView(d, style: style))
        r.scale = scale
        let img = r.nsImage
        img?.isTemplate = false
        return img
    }

    // MARK: - 노치 대응

    private func occlusionChanged() {
        guard let w = item.button?.window else { return }
        let visible = w.occlusionState.contains(.visible)
        if visible { hasBeenVisible = true; return }
        guard hasBeenVisible, !compact, store.settings.menubarStyle.rawValue >= MenubarStyle.threeDonuts.rawValue else { return }
        compact = true
        AppLog.write("[menubar] status item hidden (notch?) → compact")
        render()
    }

    private func tryExpand() {
        guard compact else { return }
        lastExpandTry = Date()
        compact = false
        render()
        // 넓힌 뒤에도 가려지면 occlusionChanged가 다시 줄인다
    }

    // MARK: - 클릭

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "지금 갱신", action: #selector(refreshNow), keyEquivalent: "r").target = self
            menu.addItem(withTitle: "설정…", action: #selector(settingsClicked), keyEquivalent: ",").target = self
            menu.addItem(withTitle: "데이터 폴더 열기", action: #selector(openData), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            let owner = sender == codexItem?.button ? codexItem! : item
            owner.menu = menu
            sender.performClick(nil)
            owner.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) } else { showPanel(from: sender) }
    }

    @objc private func refreshNow() { Task { await store.refresh(force: true) } }
    @objc private func settingsClicked() { openSettings() }
    @objc private func openData() { NSWorkspace.shared.open(AppLog.dataDir) }
}
