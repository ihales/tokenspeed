#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="TokenSpeed"
BUNDLE_ID="com.tokenspeed.TokenSpeed"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

workspace_pids() {
  local pid
  for pid in $(pgrep -x "$APP_NAME" || true); do
    if [[ "$(ps -p "$pid" -o comm=)" == "$APP_BINARY" ]]; then
      echo "$pid"
    fi
  done
}

for pid in $(workspace_pids); do
  kill "$pid"
done
"$ROOT_DIR/script/bundle.sh" debug >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run) open_app ;;
  --debug) lldb -- "$APP_BINARY" ;;
  --logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify)
    open_app
    sleep 1
    RUNNING="$(workspace_pids)"
    [[ -n "$RUNNING" ]]
    echo "$RUNNING"
    ;;
esac
