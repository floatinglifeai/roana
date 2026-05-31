#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${APP_ID:-com.roana.app}"
ACTIVITY="${ACTIVITY:-$APP_ID/.VideoReplayBenchmarkActivity}"
APK_PATH="${APK_PATH:-$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk}"
VIDEO="${VIDEO:-$ROOT_DIR/samples/iphone_0530.mp4}"
FPS="${FPS:-10}"
MAX_SECONDS="${MAX_SECONDS:-}"
ROTATION_DEGREES="${ROTATION_DEGREES:-0}"
RUN_YOLO="${RUN_YOLO:-1}"
RUN_DEPTH="${RUN_DEPTH:-1}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-360}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
DEVICE_APK_PATH="${DEVICE_APK_PATH:-/data/local/tmp/roana-debug.apk}"
DEVICE_TMP_VIDEO="${DEVICE_TMP_VIDEO:-/data/local/tmp/roana-replay.mp4}"
DEVICE_VIDEO_PATH="${DEVICE_VIDEO_PATH:-/data/data/$APP_ID/files/replay/$(basename "$VIDEO")}"
ADB_BIN="${ADB_BIN:-}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="$LOG_DIR/android-video-replay-$(basename "${VIDEO%.*}")-$TIMESTAMP.log"
RESULT_PATH="$LOG_DIR/android-video-replay-$(basename "${VIDEO%.*}")-$TIMESTAMP.json"

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().strip()))'
}

json_result() {
  local status="$1"
  local artifact="$2"
  local decision="$3"
  local details="$4"
  mkdir -p "$LOG_DIR"
  cat >"$RESULT_PATH" <<JSON
{
  "status": "$status",
  "hypothesis": "Android replays a fixed local video through the TFLite/QNN YOLO + Depth corridor stack for comparable benchmarks",
  "artifact": "$artifact",
  "result": "$RESULT_PATH",
  "decision": "$decision",
  "details": $details
}
JSON
  cat "$RESULT_PATH"
}

analysis_details() {
  printf '%s' "$1" | python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["details"]))'
}

install_apk() {
  local output_file
  local install_status
  output_file="$(mktemp)"

  "$ADB_BIN" "${DEVICE_ARG[@]}" push "$APK_PATH" "$DEVICE_APK_PATH" >/dev/null 2>&1

  set +e
  "$ADB_BIN" "${DEVICE_ARG[@]}" shell pm install -r -g -d "$DEVICE_APK_PATH" >"$output_file" 2>&1
  install_status=$?
  set -e

  if [ "$install_status" -ne 0 ] && grep -q "INSTALL_FAILED_UPDATE_INCOMPATIBLE" "$output_file"; then
    "$ADB_BIN" "${DEVICE_ARG[@]}" uninstall "$APP_ID" >/dev/null 2>&1 || true
    set +e
    "$ADB_BIN" "${DEVICE_ARG[@]}" shell pm install -r -g -d "$DEVICE_APK_PATH" >"$output_file" 2>&1
    install_status=$?
    set -e
  fi

  if [ "$install_status" -ne 0 ]; then
    cat "$output_file" >&2
    rm -f "$output_file"
    return "$install_status"
  fi

  rm -f "$output_file"
  return 0
}

wait_for_replay() {
  local started_at
  started_at="$(date +%s)"
  while true; do
    if grep -q "replay_benchmark status=finished" "$LOG_PATH" 2>/dev/null; then
      return 0
    fi
    if grep -q "replay_benchmark status=failed" "$LOG_PATH" 2>/dev/null; then
      return 1
    fi
    if [ $(( $(date +%s) - started_at )) -ge "$TIMEOUT_SECONDS" ]; then
      return 2
    fi
    sleep 1
  done
}

if [ -z "$ADB_BIN" ]; then
  if command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
  elif [ -x "$HOME/.local/android-platform-tools/platform-tools/adb" ]; then
    ADB_BIN="$HOME/.local/android-platform-tools/platform-tools/adb"
  fi
fi

if [ -z "$ADB_BIN" ]; then
  json_result "failed" "" "Install host adb before running Android video replay benchmark." "{}"
  exit 1
fi

if [ ! -f "$VIDEO" ]; then
  json_result "blocked" "" "Replay video is missing: $VIDEO." "{}"
  exit 2
fi

devices=()
while IFS= read -r device; do
  devices+=("$device")
done < <("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" {print $1}')

if [ -n "${ANDROID_SERIAL:-}" ]; then
  DEVICE_ARG=(-s "$ANDROID_SERIAL")
elif [ "${#devices[@]}" -eq 1 ]; then
  DEVICE_ARG=(-s "${devices[0]}")
elif [ "${#devices[@]}" -eq 0 ]; then
  json_result "blocked" "" "Connect one Android phone with USB debugging enabled, or set ANDROID_SERIAL." "{}"
  exit 2
else
  json_result "blocked" "" "Multiple ADB devices are connected; set ANDROID_SERIAL to choose one." "{}"
  exit 2
fi

if [ "${BUILD_FIRST:-1}" = "1" ] || [ ! -f "$APK_PATH" ]; then
  "$ROOT_DIR/scripts/build-debug.sh" >/dev/null
fi

if [ ! -f "$APK_PATH" ]; then
  json_result "failed" "" "Debug APK is missing after build." "{}"
  exit 1
fi

mkdir -p "$LOG_DIR"

if ! install_apk; then
  json_result "failed" "" "APK install failed through device-local pm install." "{}"
  exit 1
fi

"$ADB_BIN" "${DEVICE_ARG[@]}" push "$VIDEO" "$DEVICE_TMP_VIDEO" >/dev/null
"$ADB_BIN" "${DEVICE_ARG[@]}" shell run-as "$APP_ID" mkdir -p files/replay >/dev/null
"$ADB_BIN" "${DEVICE_ARG[@]}" shell run-as "$APP_ID" cp "$DEVICE_TMP_VIDEO" "files/replay/$(basename "$VIDEO")" >/dev/null
"$ADB_BIN" "${DEVICE_ARG[@]}" shell run-as "$APP_ID" chmod 600 "files/replay/$(basename "$VIDEO")" >/dev/null

model="$("$ADB_BIN" "${DEVICE_ARG[@]}" shell getprop ro.product.model | tr -d '\r')"
soc_model="$("$ADB_BIN" "${DEVICE_ARG[@]}" shell getprop ro.soc.model | tr -d '\r')"
board_platform="$("$ADB_BIN" "${DEVICE_ARG[@]}" shell getprop ro.board.platform | tr -d '\r')"
abis="$("$ADB_BIN" "${DEVICE_ARG[@]}" shell getprop ro.product.cpu.abilist | tr -d '\r')"

"$ADB_BIN" "${DEVICE_ARG[@]}" shell am force-stop "$APP_ID" >/dev/null 2>&1 || true
"$ADB_BIN" "${DEVICE_ARG[@]}" logcat -c >/dev/null
"$ADB_BIN" "${DEVICE_ARG[@]}" logcat -v time RoanaV0a:I '*:S' >"$LOG_PATH" &
logcat_pid=$!
cleanup() {
  kill "$logcat_pid" >/dev/null 2>&1 || true
  wait "$logcat_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

start_args=(
  -n "$ACTIVITY"
  --es "com.roana.app.extra.REPLAY_VIDEO_PATH" "$DEVICE_VIDEO_PATH"
  --es "com.roana.app.extra.REPLAY_FPS" "$FPS"
  --ei "com.roana.app.extra.REPLAY_ROTATION_DEGREES" "$ROTATION_DEGREES"
)
if [ -n "$MAX_SECONDS" ]; then
  start_args+=(--es "com.roana.app.extra.REPLAY_MAX_SECONDS" "$MAX_SECONDS")
fi
if [ "$RUN_YOLO" = "1" ]; then
  start_args+=(--ez "com.roana.app.extra.REPLAY_RUN_YOLO" true)
else
  start_args+=(--ez "com.roana.app.extra.REPLAY_RUN_YOLO" false)
fi
if [ "$RUN_DEPTH" = "1" ]; then
  start_args+=(--ez "com.roana.app.extra.REPLAY_RUN_DEPTH" true)
else
  start_args+=(--ez "com.roana.app.extra.REPLAY_RUN_DEPTH" false)
fi

"$ADB_BIN" "${DEVICE_ARG[@]}" shell am start "${start_args[@]}" >/dev/null

set +e
wait_for_replay
wait_status=$?
set -e

sleep 1
cleanup
trap - EXIT

if [ "$wait_status" -eq 2 ]; then
  details="{\"log_path\": \"$(printf '%s' "$LOG_PATH")\", \"timeout_seconds\": $TIMEOUT_SECONDS}"
  json_result "failed" "$LOG_PATH" "Android video replay benchmark timed out." "$details"
  exit 1
elif [ "$wait_status" -ne 0 ]; then
  escaped_log="$(tail -120 "$LOG_PATH" | json_escape)"
  json_result "failed" "$LOG_PATH" "Android video replay benchmark failed." "{\"tail\": $escaped_log}"
  exit 1
fi

analysis_json="$(
  python3 "$ROOT_DIR/scripts/analyze-v0b-log.py" \
    --log "$LOG_PATH" \
    --model "$model" \
    --soc-model "$soc_model" \
    --board-platform "$board_platform" \
    --abis "$abis" \
    --min-depth-fps "${MIN_DEPTH_FPS:-10}" \
    --require-target-soc 0 \
    --require-fp16-htp 0 \
    --require-corridor-feedback 0 \
    --require-safe-stop-proof 0 \
    --thermal-minutes-required 0 \
    --require-corridor-test 0
)"
details="$(analysis_details "$analysis_json")"
json_result "passed" "$LOG_PATH" "Android video replay benchmark completed on the fixed sample video." "$details"
