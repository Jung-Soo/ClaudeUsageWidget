**English** | [한국어](README.ko.md)

# Claude Usage Bar (macOS)

A macOS menu bar app that shows your Claude Code plan usage. If you use Codex (app or CLI), it shows Codex usage too.

It is the macOS counterpart of the [Windows widget](../windows/README.md): not a port of the Windows code, but the same behaviour written from scratch in Swift/SwiftUI. For the repository overview, see the [root README](../README.md).

<img src="docs/images/hero.png" width="420">

<img src="docs/images/panel-compact.png" width="300"> <img src="docs/images/menubar-styles.png" width="380">

## Requirements

- macOS 14 or later
- You have logged in to the Claude Code CLI with a subscription account (Pro / Max / Team / Enterprise)

## Build / run

```bash
scripts/build-app.sh --run      # builds ~/Applications/ClaudeUsageBar.app and launches it
swift test                      # unit tests
.build/debug/ClaudeUsageBar --snapshot out/   # panel and menu bar PNGs from real data; dark doc images (sample values) in out/docs/
CUB_LANG=ko .build/debug/ClaudeUsageBar --snapshot out/   # same, in Korean
```

## Data sources

| Priority | Source | When | What you get |
|---|---|---|---|
| 1 | `GET api.anthropic.com/api/oauth/usage` (undocumented) | While the CLI token is valid, every 3 minutes by default | Everything: reset times, per-model limits, credit amounts |
| 2 | Desktop app data `~/Library/Application Support/Claude/plan-usage-history.json` | Token expired and the data is under 30 minutes old | 5-hour and weekly % (15-minute steps) |
| — | `~/.claude/projects/**/*.jsonl` | Always, every 10 seconds | Today's tokens |
| Codex | `token_count` events in `~/.codex/sessions/**/rollout-*.jsonl` | Written by Codex whenever you use it; limits checked every 30 s, tokens every 10 s | Codex 5-hour and weekly % per limit, reset times, today's tokens |

- The token is **read-only** from the Keychain item `Claude Code-credentials` via `/usr/bin/security`. The app never refreshes or writes it. When it expires, the CLI refreshes it itself the next time you run `claude` in Terminal.
- On a 429 the app waits 5 → 10 → 20 → 30 minutes and keeps waiting across restarts.
- Tokens never go to disk or logs (`sk-ant-…` is masked in the log).
- Codex data comes from local logs only, with no network or auth. Codex in the ChatGPT app, the Codex CLI and the VS Code extension all write the same logs.
  - Limit % is the account-wide value reported by the Codex server, so the app uses the most recent record from any client (no summing). Today's tokens add up every session on this Mac
  - The main limit stays visible even after long idle periods and shows 0% (estimated) once its reset has passed. Extra per-model limits are hidden after 8 days without data
  - Values older than 6 hours turn gray (usage on the web or other devices shows up the next time you use Codex on this Mac)
- When the Claude CLI token expires (about every 8 hours; it is refreshed only when you use `claude` in Terminal), the panel falls back to desktop app data (the desktop app writes it only sporadically, even while running). Turn on "Auto-refresh CLI token" in Settings (off by default) and the app briefly runs the CLI so it refreshes itself (about 500 tokens per refresh). Weekly resets are computed on a 7-day cycle; the 5-hour reset is estimated from the data and marked with "~". Passed resets show 0% (estimated)
- API-key-only users (no subscription) have no 5-hour or weekly limits, so only today's tokens are shown (both Claude and Codex)

## Features

- One menu bar item with every enabled service: `◔ 13 · 27 · 11  ◔ 45` (Claude · Codex)
  - Claude has four styles (① donut only / ② donut + number / ③ three mini donuts / ④ donut + three numbers, default ④); Codex shows a donut + its highest %
  - ③ and ④ shrink to ② automatically when hidden behind the notch
- Panel: one section per service (Claude on top, Codex below, a band in between). Each section has limits, credits and today's tokens, and a status line
  - Panel size: standard (donuts) / compact (one horizontal bar per limit)
  - Click a donut or bar to switch between time left and reset time
- Services: turn Claude and Codex on or off separately. The first launch decides based on whether `~/.claude` and `~/.codex/sessions` exist. With Claude off, the app never touches the Keychain or the API
- Codex uses a single blue (70%+ orange, 90%+ red)
- Notifications: warning (85%), danger (95%), 100% reached, pace forecast (limit within 60 minutes), extra credits in use. Once per stage per reset cycle
- UI language: Korean if the system language is Korean, English otherwise. Change it under Settings → Language (the app restarts)
- Settings (right-click, or ⋯ in the panel → Settings…): services, menu bar style, panel size, Claude check interval (2/3/5/10 min), language, launch at login, notification thresholds (80·95 / 85·95 / 90·98), test notification

## App data

`~/Library/Application Support/ClaudeUsageBar/`: `state.json` (last API values, wait state), `alerts.json` (notification history), `app.log` (last 200 lines)

## Docs

- [docs/GUIDE.md](docs/GUIDE.md): install, usage and troubleshooting guide
- [CLAUDE.md](CLAUDE.md): notes Claude Code reads when building or changing the app
