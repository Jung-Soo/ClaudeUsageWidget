# Claude Usage Widget — 저장소 안내 (Claude Code용)

두 플랫폼을 한 저장소에 둔다.

- `windows/` — Windows 위젯(PowerShell 5.1 + WinForms, NSIS). **원본 [hideface/ClaudeUsageWidget](https://github.com/hideface/ClaudeUsageWidget)의 코드**이며 이 저장소에서는 고치지 않는다(동기화로만 바뀜). 사용자가 명시적으로 Windows 수정을 원하면 원본과 갈라진다는 점을 먼저 알린다
- `macos/` — macOS 메뉴바 앱(Swift). 이 저장소에서 개발한다. 작업 규칙·명령·구조는 [`macos/CLAUDE.md`](macos/CLAUDE.md)

## 원격

- `origin` = **Jung-Soo/ClaudeUsageWidget** (주 저장소, `main`)
- `upstream` = hideface/ClaudeUsageWidget (원본, Windows 위젯이 개발되는 곳)
- 공개 커밋 작성자는 GitHub noreply 주소(`26371525+Jung-Soo@users.noreply.github.com`)
- 원본에 열어 둔 PR: [#2](https://github.com/hideface/ClaudeUsageWidget/pull/2) (`macos-codex` 브랜치, 지우지 않는다)

## 원본(Windows) 업데이트 가져오기

원본은 Windows 파일을 루트(`src/`, `installer/`, `build.sh`, `README.md`)에 두고, 이 저장소는 `windows/` 아래로 옮겨 두었다. git은 병합할 때 이름 바꾸기를 따라가므로 원본이 고친 기존 파일은 대개 `windows/` 쪽에 자동으로 반영된다.

```bash
git fetch upstream
git log --oneline --stat main..upstream/main     # 무엇이 새로 왔는지 먼저 확인
git checkout main && git merge upstream/main
```

병합 뒤 확인·정리:
- 원본이 **새 파일**을 루트 `src/`·`installer/` 등에 추가했다면 → `windows/` 아래 같은 위치로 `git mv`
- 원본 **README.md** 변경 → `windows/README.md`에 반영(루트 README는 이 저장소의 개요라 원본 내용으로 덮지 않는다). 충돌하면 루트는 우리 것, 내용은 `windows/README.md`로
- 원본이 **`macos/`**(PR #1로 들어간 옛 맥 코드)를 고쳤다면 → 우리 버전 유지, 살릴 변경만 따로 옮김
- `.gitattributes`의 줄바꿈 규칙(`*.ps1 eol=crlf` 등)은 경로와 무관하게 적용되므로 그대로 둔다
- `cd macos && swift test` 후 `git push origin main`

Windows 쪽에 새 기능이 생기면(예: 1.6 작게 모드) 맥에도 가져올지 사용자에게 먼저 묻는다.

## 이 맥에서 Windows 빌드는 확인할 수 없다

`windows/build.sh`는 mingw-w64와 NSIS가 필요하다(Linux 기준 안내). 파일을 옮길 때는 상대 경로(`setup.nsi`의 `..\src\…`, `build.sh`의 `cd "$(dirname "$0")/installer"`)가 유지되는지만 확인한다.
