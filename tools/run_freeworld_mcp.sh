#!/bin/zsh
set -euo pipefail

ROOT_DIR="/Users/egorsitko/Desktop/проэкты/Симулятор свободного мира"
DERIVED_DIR="$ROOT_DIR/.derived"
LOG_PATH="$ROOT_DIR/playtest_logs/freeworld_mcp_build.log"

mkdir -p "$ROOT_DIR/playtest_logs"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project "$ROOT_DIR/FreeWorldSimulator.xcodeproj" \
  -scheme FreeWorldMac \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DIR" \
  build >"$LOG_PATH" 2>&1

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project "$ROOT_DIR/FreeWorldSimulator.xcodeproj" \
  -scheme FreeWorldMCP \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DIR" \
  build >>"$LOG_PATH" 2>&1

BIN_PATH="$(find "$DERIVED_DIR" "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/FreeWorldMCP' -type f -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n 1)"
APP_EXECUTABLE_PATH="$(find "$DERIVED_DIR" "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/FreeWorldMac.app/Contents/MacOS/FreeWorldMac' -type f -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n 1)"
APP_PATH="$(dirname "$(dirname "$(dirname "$APP_EXECUTABLE_PATH")")")"

if [[ -z "$BIN_PATH" || ! -x "$BIN_PATH" ]]; then
  echo "Не найден собранный FreeWorldMCP" >&2
  exit 1
fi

if [[ -z "$APP_EXECUTABLE_PATH" || -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Не найдено собранное приложение FreeWorldMac.app" >&2
  exit 1
fi

export FREEWORLD_ROOT_DIR="$ROOT_DIR"
export FREEWORLD_LIVE_APP_PATH="$APP_PATH"
export FREEWORLD_LIVE_HOST="127.0.0.1"
export FREEWORLD_LIVE_PORT="47831"

exec "$BIN_PATH"
