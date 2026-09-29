#!/usr/bin/env bash
# release 빌드 → ~/Applications/ClaudeUsageBar.app (ad-hoc 서명). 사용: scripts/build-app.sh [--run]
# 저장소가 iCloud 동기화 폴더(Documents 등)에 있으면 동기화가 번들에 확장 속성을 붙여 서명이 거부되므로,
# 번들은 동기화 밖(기본 ~/Applications, APP_DIR로 변경)에 만든다.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="${APP_DIR:-$HOME/Applications}/ClaudeUsageBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ClaudeUsageBar" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "built $APP"
if [[ "${1:-}" == "--run" ]]; then
  pkill -x ClaudeUsageBar 2>/dev/null || true
  sleep 0.5
  open "$APP"
fi
