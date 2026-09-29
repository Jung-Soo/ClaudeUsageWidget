# ClaudeUsageWidget

Claude Code 플랜 사용량을 바탕화면에 띄워 두는 Windows용 미니 위젯입니다.

- 카드: 주간 한도 큰 링 + 리셋까지 남은 시간, 5시간 / 사용률이 가장 높은 모델 주간 한도 작은 링 (사용률에 따라 색이 주황 → 빨강)
- 플랜 표시 (예: Team · Max 5x), 마지막 갱신 시각
- 추가 사용 크레딧(이번 달 사용액, 월 한도가 있으면 `/ 한도`)
- 오늘 사용한 토큰 합계 (로컬 세션 로그 집계)
- 작업표시줄 요약: 트레이 왼쪽에 `5시간 · 주간 · 모델` 사용률 숫자 표시
- 작은 모드: 도넛 대신 한도별 가로 막대 한 줄씩 (우클릭 → 크기 → 작게)
- 알림: 85% 경고, 95% 위험(위젯 앞으로 + 깜빡임), 100% 도달, 사용 속도 예측, 크레딧 사용 시작
- 라이트/다크 테마, 바탕화면 고정 / 일반 창 / 항상 위, 트레이 아이콘

## 요구 사항

- Windows 10 1809 이상 또는 Windows 11 (추가 설치 없음: Windows PowerShell 5.1 + .NET WinForms 사용)
- Claude Code CLI에 **구독 계정**(Pro / Max / Team / Enterprise)으로 로그인되어 있을 것
  - `%USERPROFILE%\.claude\.credentials.json` 의 OAuth 토큰으로 한도를 조회합니다
  - API 키 전용 사용자는 한도가 표시되지 않습니다 (오늘 토큰은 표시됨)

## 설치

[Releases](../../releases)에서 `ClaudeUsageWidget-Setup-x.y.z.zip` (또는 `.exe`)을 받아 압축을 풀고 `ClaudeUsageWidget-Setup-x.y.z.exe` 를 실행합니다.

- 관리자 권한 불필요, 현재 사용자에게만 설치 (`%LOCALAPPDATA%\Programs\ClaudeUsageWidget`)
- 시작 메뉴 바로가기, 선택 시 로그인 자동 실행
- 제거: 설정 → 앱 → Claude Usage Widget
- 코드 서명이 없어 처음 실행 시 SmartScreen 경고가 뜰 수 있습니다 (추가 정보 → 실행)
- 백신이 머신러닝 기반으로 오탐할 수 있습니다 (예: Defender `Trojan:Win32/Wacatac.C!ml`). 아래 「주의」 참고

## 사용법

- 드래그로 이동, ⟳ 로 즉시 갱신, `…` 로 메뉴 열기, 링 클릭으로 남은 시간 ↔ 리셋 시각 전환
- 작업표시줄 숫자: 마우스를 올리면 항목 설명, 클릭하면 카드 열기, 우클릭하면 메뉴
- 우클릭 메뉴: 테마, 크기(기본/작게), 표시 방식, 한도 조회 주기(2/3/5/10분), 알림 설정, 투명도, 작업표시줄 요약 표시, 자동 실행, 오류 로그
- 작업표시줄 요약은 트레이 옆에 작은 창을 겹쳐 띄우는 방식이라 전체화면 앱·발표 중에는 숨고, 세로 작업표시줄은 지원하지 않습니다

## 동작 방식

| 항목 | 출처 | 주기 |
|---|---|---|
| 한도·크레딧 | `GET https://api.anthropic.com/api/oauth/usage` (비공식, Claude Code `/usage` 와 동일) | 기본 3분 |
| 오늘 토큰 | `%USERPROFILE%\.claude\projects\**\*.jsonl` 증분 읽기 (새 줄만) | 10초 |

- 429(호출 제한) 시 5 → 10 → 20 → 30분으로 대기 시간을 늘리며, 대기 중에는 수동 갱신·재시작도 호출하지 않습니다.
- 액세스 토큰이 만료되면 refresh token으로 갱신해 `.credentials.json` 에 다시 저장합니다 (처음 한 번 `.credentials.json.widget-bak` 백업). 메뉴에서 끌 수 있습니다.
- 위젯 데이터: `%LOCALAPPDATA%\ClaudeUsageWidget` (`usage.txt`, `usage-raw.json`, `fetch.log`(최근 200줄), `settings.json`)
- `ClaudeUsageWidget.exe` 는 PowerShell을 콘솔 없이(`CREATE_NO_WINDOW`) 띄우는 48KB 런처입니다. Windows Terminal이 기본 터미널이어도 창이 생기지 않습니다.

## 주의

- 한도 조회 API는 문서화되지 않은 엔드포인트라 응답 형식이 바뀌면 동작하지 않을 수 있습니다. 오류는 우클릭 → 오류 로그 열기로 확인하세요.
- 숨겨진 PowerShell이 인증 파일을 읽고 토큰 엔드포인트를 호출하므로 EDR/백신 정책에 따라 탐지될 수 있습니다. 사내 배포 전 보안 담당자와 공유를 권장합니다.
- 설치 파일에 코드 서명이 없어 Windows Defender 등이 `Trojan:Win32/Wacatac.C!ml` 같은 머신러닝 기반 일반 탐지로 오탐할 수 있습니다. 같은 소스를 다시 빌드하면 결과가 달라지기도 했습니다. 걱정되면 소스(`src/`)를 직접 확인하고 `build.sh` 로 빌드해서 쓰세요.
- PowerShell 실행을 막는 정책(AppLocker, Constrained Language Mode)에서는 동작하지 않습니다.

## 구조 / 빌드

```
src/
  widget.ps1         위젯 UI (WinForms, GDI 렌더링, 알림)
  fetch-usage.ps1    수집기 (API 조회, 토큰 갱신, jsonl 증분 집계) — 위젯 안의 별도 runspace에서 실행
installer/
  launcher.c/.rc     콘솔 없는 런처 (mingw-w64)
  setup.nsi          NSIS 설치 스크립트
  stop-widget.ps1    설치/제거 시 실행 중인 위젯 종료
  app.ico
build.sh             런처 + 설치 파일 빌드
```

```bash
sudo apt install gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64 nsis
./build.sh      # installer/ClaudeUsageWidget-Setup-x.y.z.exe
```

버전은 `installer/setup.nsi` 의 `VERSION` 과 `installer/launcher.rc` 에서 올립니다.
