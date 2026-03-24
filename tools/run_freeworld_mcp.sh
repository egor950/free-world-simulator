#!/bin/zsh
set -euo pipefail

ROOT_DIR="/Users/egorsitko/Desktop/проэкты/Симулятор свободного мира"
DERIVED_DIR="$ROOT_DIR/.derived"
LOG_PATH="$ROOT_DIR/playtest_logs/freeworld_mcp_build.log"
CACHE_PATH="$ROOT_DIR/playtest_logs/freeworld_mcp_paths.env"
XCODE_DERIVED_DIR="$ROOT_DIR/.xcode_derived"
XCODE_HOME="$ROOT_DIR/.xcode_home"

mkdir -p "$XCODE_DERIVED_DIR" "$XCODE_HOME"

mkdir -p "$ROOT_DIR/playtest_logs"

latest_match() {
  local pattern="$1"
  find "$DERIVED_DIR" "$XCODE_DERIVED_DIR" -path "$pattern" -type f -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -n 1
}

use_product_paths() {
  local bin_path="$1"
  local app_executable_path="$2"

  BIN_PATH="$bin_path"
  APP_EXECUTABLE_PATH="$app_executable_path"

  if [[ -n "${APP_EXECUTABLE_PATH:-}" ]]; then
    APP_PATH="$(dirname "$(dirname "$(dirname "$APP_EXECUTABLE_PATH")")")"
  else
    APP_PATH=""
  fi
}

product_paths_are_valid() {
  [[ -n "${BIN_PATH:-}" && -x "${BIN_PATH:-}" ]] || return 1
  [[ -n "${APP_EXECUTABLE_PATH:-}" && -x "${APP_EXECUTABLE_PATH:-}" ]] || return 1
  [[ -n "${APP_PATH:-}" && -d "${APP_PATH:-}" ]] || return 1
  return 0
}

load_cached_products() {
  [[ -f "$CACHE_PATH" ]] || return 1

  local cached_bin_path=""
  local cached_app_executable_path=""
  local line key value

  while IFS= read -r line; do
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      BIN_PATH) cached_bin_path="$value" ;;
      APP_EXECUTABLE_PATH) cached_app_executable_path="$value" ;;
    esac
  done < "$CACHE_PATH"

  use_product_paths "$cached_bin_path" "$cached_app_executable_path"
  product_paths_are_valid
}

save_cached_products() {
  product_paths_are_valid || return 0

  {
    printf 'BIN_PATH=%s\n' "$BIN_PATH"
    printf 'APP_EXECUTABLE_PATH=%s\n' "$APP_EXECUTABLE_PATH"
  } > "$CACHE_PATH"
}

find_products() {
  if load_cached_products; then
    return
  fi

  use_product_paths \
    "$(latest_match '*/Build/Products/Debug/FreeWorldMCP')" \
    "$(latest_match '*/Build/Products/Debug/FreeWorldMac.app/Contents/MacOS/FreeWorldMac')"

  save_cached_products
}

project_is_newer_than() {
  local target="$1"
  [[ -z "$target" || ! -e "$target" ]] && return 0
  find \
    "$ROOT_DIR/Sources" \
    "$ROOT_DIR/Resources" \
    "$ROOT_DIR/FreeWorldSimulator.xcodeproj" \
    "$ROOT_DIR/project.yml" \
    -type f -newer "$target" -print -quit 2>/dev/null \
    | grep -q .
}

build_if_needed() {
  local need_build=0

  find_products

  if [[ "${FREEWORLD_FORCE_REBUILD:-0}" == "1" ]]; then
    need_build=1
  fi
  if [[ -z "${BIN_PATH:-}" || ! -x "${BIN_PATH:-}" ]]; then
    need_build=1
  fi
  if [[ -z "${APP_EXECUTABLE_PATH:-}" || ! -x "${APP_EXECUTABLE_PATH:-}" ]]; then
    need_build=1
  fi
  if [[ $need_build -eq 0 ]] && project_is_newer_than "$BIN_PATH"; then
    need_build=1
  fi
  if [[ $need_build -eq 0 ]] && project_is_newer_than "$APP_EXECUTABLE_PATH"; then
    need_build=1
  fi

  if [[ $need_build -eq 0 ]]; then
    save_cached_products
    echo "freeworld-mcp: using existing build" >&2
    return
  fi

  echo "freeworld-mcp: building project" >&2

  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  HOME="$XCODE_HOME" \
  xcodebuild \
    -project "$ROOT_DIR/FreeWorldSimulator.xcodeproj" \
    -scheme FreeWorldMac \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    -derivedDataPath "$XCODE_DERIVED_DIR" \
    build >"$LOG_PATH" 2>&1

  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  HOME="$XCODE_HOME" \
  xcodebuild \
    -project "$ROOT_DIR/FreeWorldSimulator.xcodeproj" \
    -scheme FreeWorldMCP \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    -derivedDataPath "$XCODE_DERIVED_DIR" \
    build >>"$LOG_PATH" 2>&1

  find_products
  save_cached_products
}

build_if_needed

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
