**English** | [한국어](README.ko.md)

# Claude Usage Widget

A small tool that keeps your Claude Code plan usage (5-hour, weekly and per-model limits) always in view. It runs on **Windows** and **macOS**; the macOS version also shows **Codex** usage.

<img src="macos/docs/images/hero.png" width="420">

## Platforms

| | Windows | macOS |
|---|---|---|
| Form | Desktop card widget + taskbar summary | Menu bar item + drop-down panel |
| Services | Claude Code | Claude Code, Codex (ChatGPT app, CLI, VS Code extension) |
| Built with | Windows PowerShell 5.1 + WinForms (nothing to install) | Swift / SwiftUI, macOS 14+ |
| Install | Installer from the original repo's [Releases](https://github.com/hideface/ClaudeUsageWidget/releases) | Shared zip, or build from source |
| UI language | Korean | English / Korean (follows the system language) |
| Docs | [windows/README.md](windows/README.md) (Korean) | [macos/README.md](macos/README.md) · [Install & user guide](macos/docs/GUIDE.md) |

## Common features

- 5-hour, weekly and per-model weekly limits (%) with time to reset; the limit you will hit first is highlighted
- Extra usage credits (spent this month / monthly cap) and today's tokens (from local session logs)
- Notifications: 85% warning, 95% danger, 100% reached, pace forecast, extra credits in use
- Standard and compact (horizontal bars) views; click to switch between time left and reset time
- When the usage API rate-limits (429), waits 5 → 10 → 20 → 30 minutes and keeps the wait across restarts

## Platform differences

| | Windows | macOS |
|---|---|---|
| Claude token | `%USERPROFILE%\.claude\.credentials.json`. When it expires, the widget refreshes it with the refresh token and saves it back (can be turned off) | **Read-only** from the Keychain. When it expires, the Claude Code CLI refreshes it itself (optional "Auto-refresh CLI token", off by default) |
| While the token is expired | Last value | Claude desktop app data, computed/estimated reset times, then the last value |
| Codex | — | Limits and today's tokens from local logs (no login or network needed) |
| Lives in | Desktop card (pinned to desktop / normal / always on top), tray icon | Menu bar (4 styles, shrinks automatically when hidden behind the notch) |

## Repository layout

```
windows/   Windows widget (PowerShell + WinForms, NSIS installer) — taken from the original repository
macos/     macOS menu bar app (Swift package: UsageCore library + app, unit tests)
```

## Origin and maintenance

- The Windows widget was created at [hideface/ClaudeUsageWidget](https://github.com/hideface/ClaudeUsageWidget) and is still developed there. This repository is a fork that pulls in Windows updates when needed.
- The macOS version was written from scratch in this fork (not a port of the Windows code, but the same behaviour in Swift). Its first version was merged upstream ([#1](https://github.com/hideface/ClaudeUsageWidget/pull/1)); later versions (Codex, combined menu bar item, token-expiry handling, English UI) are maintained here.

## Notes

- Limits come from `https://api.anthropic.com/api/oauth/usage`, an undocumented endpoint. It may stop working if the response format changes.
- Neither app is code-signed or notarized, so the OS warns on first launch (Windows SmartScreen, macOS Gatekeeper). Before rolling out inside a company, share it with your security team.
