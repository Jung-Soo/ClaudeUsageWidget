/* ClaudeUsageWidget launcher: starts widget.ps1 with powershell.exe and NO console window.
 * CREATE_NO_WINDOW means no console is ever allocated, so Windows Terminal (default terminal
 * handoff) has nothing to attach to. GUI subsystem, exits immediately after spawning. */
#include <windows.h>
#include <wchar.h>

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, LPWSTR cmdLine, int nShow)
{
    wchar_t dir[MAX_PATH], ps[MAX_PATH], line[4 * MAX_PATH], script[MAX_PATH];
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    wchar_t *slash;

    (void)hInst; (void)hPrev; (void)cmdLine; (void)nShow;

    if (!GetModuleFileNameW(NULL, dir, MAX_PATH)) return 1;
    slash = wcsrchr(dir, L'\\');
    if (slash) *slash = L'\0';

    if (!GetSystemDirectoryW(ps, MAX_PATH)) return 1;           /* 64-bit build -> real System32 */
    wcsncat(ps, L"\\WindowsPowerShell\\v1.0\\powershell.exe", MAX_PATH - wcslen(ps) - 1);

    _snwprintf(script, MAX_PATH, L"%ls\\widget.ps1", dir);
    script[MAX_PATH - 1] = L'\0';
    if (GetFileAttributesW(script) == INVALID_FILE_ATTRIBUTES) {
        MessageBoxW(NULL, L"widget.ps1 을 찾을 수 없습니다. 다시 설치해 주세요.", L"Claude Usage Widget", MB_ICONERROR);
        return 1;
    }

    _snwprintf(line, 4 * MAX_PATH,
               L"\"%ls\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%ls\"",
               ps, script);
    line[4 * MAX_PATH - 1] = L'\0';

    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcessW(ps, line, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                        NULL, dir, &si, &pi)) {
        MessageBoxW(NULL, L"PowerShell 을 실행하지 못했습니다.", L"Claude Usage Widget", MB_ICONERROR);
        return 1;
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
