; ClaudeUsageWidget installer (NSIS 3, per-user, no admin)
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"

!define APPNAME   "Claude Usage Widget"
!define APPKEY    "ClaudeUsageWidget"
!define VERSION   "1.5.0"
!define PUBLISHER "WineSOFT IT"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPKEY}"
!define RUNKEY    "Software\Microsoft\Windows\CurrentVersion\Run"
!define PSEXE     "$WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
!define CONHOST   "$WINDIR\System32\conhost.exe"
!define LAUNCHER  "$INSTDIR\ClaudeUsageWidget.exe"
!define PSARGS    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$INSTDIR\widget.ps1"'

Name "${APPNAME}"
OutFile "ClaudeUsageWidget-Setup-${VERSION}.exe"
InstallDir "$LOCALAPPDATA\Programs\${APPKEY}"
InstallDirRegKey HKCU "${UNINSTKEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${PUBLISHER}"

!define MUI_ICON "app.ico"
!define MUI_UNICON "app.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "Claude Code의 5시간·주간·모델별 한도와 오늘 토큰, 크레딧 사용량을 바탕화면에 보여주는 위젯입니다.$\r$\n$\r$\n필요 조건: Windows 10(1809 이상) 또는 11, Claude Code CLI 구독 계정 로그인$\r$\n$\r$\n관리자 권한 없이 현재 사용자에게만 설치됩니다."
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "위젯 바로 실행"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchWidget

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Korean"

VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1042 "ProductName" "${APPNAME}"
VIAddVersionKey /LANG=1042 "CompanyName" "${PUBLISHER}"
VIAddVersionKey /LANG=1042 "FileDescription" "${APPNAME} 설치 프로그램"
VIAddVersionKey /LANG=1042 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1042 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1042 "LegalCopyright" "${PUBLISHER}"


Function LaunchWidget
  Exec '"${LAUNCHER}"'
FunctionEnd

Function .onInit
  ; Windows 10 1809(build 17763) 미만이면 중단
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuildNumber"
  ${If} $0 != ""
  ${AndIf} $0 < 17763
    MessageBox MB_ICONSTOP "Windows 10 1809 이상에서만 설치할 수 있습니다. (현재 빌드 $0)"
    Abort
  ${EndIf}
FunctionEnd

Section "위젯 (필수)" SecMain
  SectionIn RO
  ; 실행 중인 위젯 종료
  InitPluginsDir
  File "/oname=$PLUGINSDIR\stop-widget.ps1" "stop-widget.ps1"
  nsExec::Exec '"${PSEXE}" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\stop-widget.ps1"'
  Pop $0

  SetOutPath "$INSTDIR"
  File "..\src\widget.ps1"
  File "..\src\fetch-usage.ps1"
  File "stop-widget.ps1"
  File "ClaudeUsageWidget.exe"
  File "app.ico"
  ; 예전 zip 버전 설치 스크립트가 남긴 파일 정리
  Delete "$INSTDIR\install.ps1"

  CreateShortcut "$SMPROGRAMS\${APPNAME}.lnk" "${LAUNCHER}" "" "${LAUNCHER}" 0

  ; 이전 버전이 남긴 자동 실행 값(conhost 방식)이 있으면 런처로 교체
  ReadRegStr $1 HKCU "${RUNKEY}" "${APPKEY}"
  ${If} $1 != ""
    WriteRegStr HKCU "${RUNKEY}" "${APPKEY}" '"${LAUNCHER}"'
  ${EndIf}

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr   HKCU "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr   HKCU "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr   HKCU "${UNINSTKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr   HKCU "${UNINSTKEY}" "DisplayIcon" "${LAUNCHER}"
  WriteRegStr   HKCU "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKCU "${UNINSTKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr   HKCU "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${UNINSTKEY}" "EstimatedSize" 120
SectionEnd

Section "Windows 시작 시 자동 실행" SecAuto
  WriteRegStr HKCU "${RUNKEY}" "${APPKEY}" '"${LAUNCHER}"'
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} "위젯 프로그램과 시작 메뉴 바로가기"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecAuto} "로그인하면 위젯이 자동으로 뜹니다. 나중에 위젯 우클릭 메뉴에서 끌 수 있어요."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  nsExec::Exec '"${PSEXE}" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\stop-widget.ps1"'
  Pop $0
  DeleteRegValue HKCU "${RUNKEY}" "${APPKEY}"
  DeleteRegKey HKCU "${UNINSTKEY}"
  Delete "$SMPROGRAMS\${APPNAME}.lnk"
  Delete "$INSTDIR\widget.ps1"
  Delete "$INSTDIR\fetch-usage.ps1"
  Delete "$INSTDIR\stop-widget.ps1"
  Delete "$INSTDIR\app.ico"
  Delete "$INSTDIR\ClaudeUsageWidget.exe"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  ; 설정/로그/캐시 (Claude Code 자격 증명과 로그는 건드리지 않음)
  RMDir /r "$LOCALAPPDATA\ClaudeUsageWidget"
SectionEnd
