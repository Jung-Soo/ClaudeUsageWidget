import SwiftUI
import UsageCore

/// 드롭다운 A안: 큰 도넛(지금 걸린 한도) + 작은 도넛(나머지) + (Codex 섹션) + 크레딧·오늘 토큰.
struct PanelView: View {
    let store: UsageStore
    var onOpenSettings: () -> Void = {}
    var onOpenData: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            content(now: ctx.date)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let d = store.display
        let codex = store.settings.showCodex ? store.codex : nil
        VStack(spacing: 0) {
            header(d)
            hero(d, now: now, size: codex == nil ? 132 : 108)
                .padding(.top, codex == nil ? 18 : 14).padding(.bottom, codex == nil ? 16 : 12)
            if !d.others.isEmpty {
                Divider()
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          spacing: 12) {
                    ForEach(d.others) { small($0, d: d, now: now) }
                }
                .padding(.vertical, 12)
            }
            if let codex {
                Divider()
                codexSection(codex, now: now).padding(.vertical, 12)
            }
            Divider()
            HStack(alignment: .top) {
                stat("크레딧", credit(d.credit))
                stat(codex == nil ? "오늘 토큰" : "Claude 오늘 토큰", Format.tokens(store.tokens.total))
                    .help(tokenBreakdown)
            }
            .padding(.top, 12)
            footer(d, codex: codex, now: now)
                .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private func header(_ d: DisplayState) -> some View {
        HStack(spacing: 6) {
            Text("Claude").font(.system(size: 14, weight: .medium))
            if let plan = d.plan { Text(plan).font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer()
            Circle().fill(Palette.statusDot(d.status)).frame(width: 7, height: 7)
            Button { Task { await store.refresh(force: true) } } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: store.isRefreshing)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("지금 갱신")
            .padding(.leading, 4)
            Menu {
                Button("지금 갱신") { Task { await store.refresh(force: true) } }
                Button("설정…", action: onOpenSettings)
                Button("데이터 폴더 열기", action: onOpenData)
                Divider()
                Button("종료", action: onQuit)
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func hero(_ d: DisplayState, now: Date, size: CGFloat) -> some View {
        if let a = d.active {
            VStack(spacing: 10) {
                ZStack {
                    Donut(percent: a.percent, color: Palette.color(for: a, stale: d.isStale(a)), lineWidth: size / 10)
                    VStack(spacing: 2) {
                        Text("\(Format.percent(a.percent))%")
                            .font(.system(size: size * 0.23, weight: .medium)).monospacedDigit()
                        Text(a.name).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: size, height: size)
                Text(Format.left(until: a.resetsAt, now: now).map { "\($0) 후 리셋" } ?? "리셋 시각 모름")
                    .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
        } else {
            VStack(spacing: 10) {
                Donut(percent: 0, color: Palette.stale, lineWidth: size / 10).frame(width: size, height: size)
                Text("아직 데이터가 없어요").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func codexSection(_ c: CodexDisplay, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Codex").font(.system(size: 14, weight: .medium))
                if let plan = c.plan { Text(plan).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            if let a = c.active {
                HStack(spacing: 16) {
                    ZStack {
                        Donut(percent: a.percent, color: Palette.color(for: a, stale: c.isStale), lineWidth: 8)
                        Text("\(Format.percent(a.percent))%").font(.system(size: 18, weight: .medium)).monospacedDigit()
                    }
                    .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        Text(Format.left(until: a.resetsAt, now: now).map { "\($0) 후 리셋" } ?? "리셋됨")
                            .font(.system(size: 12)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
            }
            if !c.others.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          spacing: 12) {
                    ForEach(c.others) { small($0, stale: c.isStale, now: now) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func small(_ r: LimitRow, d: DisplayState, now: Date) -> some View {
        small(r, stale: d.isStale(r), now: now)
    }

    private func small(_ r: LimitRow, stale: Bool, now: Date) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Donut(percent: r.percent, color: Palette.color(for: r, stale: stale), lineWidth: 5)
                Text(Format.percent(r.percent)).font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.system(size: 12)).lineLimit(1)
                Text(Format.left(until: r.resetsAt, now: now) ?? "-")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
    }

    private func stat(_ label: String, _ value: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            value.font(.system(size: 14, weight: .medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View { stat(label, Text(value)) }

    private func credit(_ c: Credit?) -> Text {
        guard let c, c.enabled, let used = Format.money(c.used, currency: c.currency) else { return Text("사용 안 함") }
        if let limit = Format.money(c.limit, currency: c.currency) {
            return Text(used) + Text(" / \(limit)").font(.system(size: 11, weight: .regular)).foregroundColor(.secondary)
        }
        return Text(used)
    }

    private var tokenBreakdown: String {
        let t = store.tokens
        return "입력 \(Format.tokens(t.input)) · 출력 \(Format.tokens(t.output)) · 캐시 쓰기 \(Format.tokens(t.cacheWrite)) · 캐시 읽기 \(Format.tokens(t.cacheRead)) · 메시지 \(t.messages)건"
    }

    private func footer(_ d: DisplayState, codex: CodexDisplay?, now: Date) -> some View {
        let (line, warn) = FooterText.make(d, now: now)
        return VStack(spacing: 3) {
            footerLine(codex == nil ? line : "Claude " + line, warn: warn)
            if let codex {
                let ago = Format.ago(codex.asOf, now: now)
                footerLine(codex.isStale ? "Codex \(ago) 값 · Codex를 쓰면 갱신돼요" : "Codex \(ago) 사용", warn: codex.isStale)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func footerLine(_ text: String, warn: Bool) -> some View {
        Text(text)
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(warn ? AnyShapeStyle(Palette.warn) : AnyShapeStyle(.tertiary))
            .multilineTextAlignment(.center)
    }
}

enum FooterText {
    /// (문구, 경고색 여부)
    static func make(_ d: DisplayState, now: Date) -> (String, Bool) {
        let ago = d.asOf.map { Format.ago($0, now: now) }
        let stale = !d.staleRowIDs.isEmpty && d.staleRowIDs.count == d.rows.count
        switch d.status {
        case .rateLimited(let until):
            let wait = Format.left(until: until, now: now) ?? "잠시"
            return ("호출 제한 · \(wait) 뒤 재시도" + (ago.map { " · \($0) 값" } ?? ""), true)
        case .error(let m):
            return ("조회 실패(\(m))" + (ago.map { " · \($0) 값" } ?? ""), true)
        case .auth:
            return ("인증 실패 · 터미널에서 claude 다시 로그인", true)
        case .noCredential where d.source != .desktopHistory:
            return ("Claude Code CLI 로그인이 필요해요", true)
        case .tokenExpired where d.source != .desktopHistory:
            return ("CLI 토큰 만료 · 터미널에서 claude를 실행하면 갱신돼요", true)
        default:
            break
        }
        if d.source == .desktopHistory {
            let base = "데스크톱 앱 기록 · \(ago ?? "-")"
            return (stale ? base + " 값" : base, stale)
        }
        if let ago { return (stale ? "\(ago) 값" : "\(ago) 갱신", stale) }
        return ("불러오는 중…", false)
    }
}
