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

사용자가 "원본 업데이트 반영해줘"라고 하면:

```bash
tools/sync-upstream.sh --push
```

스크립트가 하는 일(손이 가지 않게):
- 원본 새 커밋이 없으면 그냥 끝
- 병합 후 루트 `README.md`는 항상 이 저장소 것(두 플랫폼 개요)으로 되돌림
- `windows/README.md`는 원본 README를 **그대로 복사**하고 맨 위 안내 한 줄과 링크(`../../releases` → 원본 Releases, `macos/` → `../macos/`)만 고쳐 다시 만듦 → 이 파일은 직접 고치지 않는다
- 원본은 Windows 파일을 루트(`src/`, `installer/`, `build.sh`)에 두지만 이 저장소는 `windows/` 아래에 둔다. 기존 파일 수정은 git이 이름 바꾸기를 따라가 `windows/`에 반영하고, 원본이 새로 넣은 파일은 git이 `windows/` 아래로 옮겨 둔 것을 받아들임
- macOS 테스트 → 병합 커밋 → `--push`면 포크에 push

종료 코드: `0` 완료(또는 새 커밋 없음) · `1` main이 아니거나 커밋 안 된 변경 · `2` 자동으로 못 푼 충돌(병합 진행 중으로 남김: `macos/` 쪽이면 우리 버전 유지, 그 밖엔 내용을 보고 정리 후 `git commit`) · `3` macOS 테스트 실패(커밋 안 함)

`tools/sync-upstream.sh --readme-only`는 `windows/README.md`만 원본 기준으로 다시 만든다.

시험(2026-10-02, 가짜 원본 커밋으로 끝까지 실행): README 추가 줄 → `windows/README.md`에 자동 반영, 루트 README 유지, `src/widget.ps1` 수정 → `windows/src/`에 반영(CRLF 유지), 새 `src/helper.ps1` → `windows/src/helper.ps1`, 병합 커밋까지 종료 코드 0.

Windows 쪽에 새 기능이 생기면(예: 1.6 작게 모드) 맥에도 가져올지 사용자에게 먼저 묻는다.

## 이 맥에서 Windows 빌드는 확인할 수 없다

`windows/build.sh`는 mingw-w64와 NSIS가 필요하다(Linux 기준 안내). 파일을 옮길 때는 상대 경로(`setup.nsi`의 `..\src\…`, `build.sh`의 `cd "$(dirname "$0")/installer"`)가 유지되는지만 확인한다.
