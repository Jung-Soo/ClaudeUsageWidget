#!/usr/bin/env bash
# Builds the launcher (mingw-w64) and the NSIS installer.
#   Ubuntu/Debian: sudo apt install gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64 nsis
set -euo pipefail
cd "$(dirname "$0")/installer"

x86_64-w64-mingw32-windres launcher.rc -O coff -o launcher.res
x86_64-w64-mingw32-gcc -O2 -s -municode -mwindows -finput-charset=UTF-8 -Wall \
  -o ClaudeUsageWidget.exe launcher.c launcher.res
makensis -V2 setup.nsi

ls -la ClaudeUsageWidget-Setup-*.exe
