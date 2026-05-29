#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${APP_ID:-com.roana.app}"
ACTIVITY="${ACTIVITY:-$APP_ID/.MainActivity}"
APK_PATH="${APK_PATH:-$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk}"
LOG_SECONDS="${LOG_SECONDS:-30}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
MODEL="${MODEL:-all}"
REQUIRE_QNN_SUCCESS="${REQUIRE_QNN_SUCCESS:-1}"
ADB_BIN="${ADB_BIN:-}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="$LOG_DIR/qnn-smoke-$TIMESTAMP.log"
DEBUG_QNN_YOLO_EXTRA="com.roana.app.extra.DEBUG_QNN_YOLO_SMOKE"
DEBUG_QNN_DEPTH_EXTRA="com.roana.app.extra.DEBUG_QNN_DEPTH_SMOKE"

json_result() {
  local status="$1"
  local artifact="$2"
  local decision="$3"
  cat <<JSON
{
  "status": "$status",
  "hypothesis": "QNN delegate compatibility can be diagnosed independently for YOLO and Depth Anything",
  "artifact": "$artifact",
  "decision": "$decision"
}
JSON
}

if [ -z "$ADB_BIN" ]; then
  if command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
  elif [ -x "$HOME/.local/android-platform-tools/platform-tools/adb" ]; then
    ADB_BIN="$HOME/.local/android-platform-tools/platform-tools/adb"
  fi
fi

if [ -z "$ADB_BIN" ]; then
  json_result "failed" "" "Install host adb before running the QNN smoke gate."
  exit 1
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
  json_result "blocked" "" "Connect one Android phone with USB debugging enabled, or set ANDROID_SERIAL."
  exit 2
else
  json_result "blocked" "" "Multiple ADB devices are connected; set ANDROID_SERIAL to choose one."
  exit 2
fi

case "$MODEL" in
  all)
    require_yolo=1
    require_depth=1
    ;;
  yolo)
    require_yolo=1
    require_depth=0
    ;;
  depth)
    require_yolo=0
    require_depth=1
    ;;
  *)
    json_result "failed" "" "MODEL must be one of: all, yolo, depth."
    exit 1
    ;;
esac

if [ "${BUILD_FIRST:-0}" = "1" ] || [ ! -f "$APK_PATH" ]; then
  "$ROOT_DIR/scripts/build-debug.sh" >/dev/null
fi

if [ ! -f "$APK_PATH" ]; then
  json_result "failed" "" "Debug APK is missing after build."
  exit 1
fi

ADB_BIN="$ADB_BIN" "$ROOT_DIR/scripts/install-debug.sh" >/dev/null

mkdir -p "$LOG_DIR"
"$ADB_BIN" "${DEVICE_ARG[@]}" shell am force-stop "$APP_ID" >/dev/null 2>&1 || true
"$ADB_BIN" "${DEVICE_ARG[@]}" logcat -c >/dev/null

start_args=(-n "$ACTIVITY")
if [ "$require_yolo" = "1" ]; then
  start_args+=(--ez "$DEBUG_QNN_YOLO_EXTRA" true)
fi
if [ "$require_depth" = "1" ]; then
  start_args+=(--ez "$DEBUG_QNN_DEPTH_EXTRA" true)
fi
"$ADB_BIN" "${DEVICE_ARG[@]}" shell am start "${start_args[@]}" >/dev/null

set +e
if command -v timeout >/dev/null 2>&1; then
  timeout "${LOG_SECONDS}s" "$ADB_BIN" "${DEVICE_ARG[@]}" logcat -v time RoanaV0a:I '*:S' >"$LOG_PATH"
else
  "$ADB_BIN" "${DEVICE_ARG[@]}" logcat -v time RoanaV0a:I '*:S' >"$LOG_PATH" &
  logcat_pid=$!
  sleep "$LOG_SECONDS"
  kill "$logcat_pid" >/dev/null 2>&1 || true
  wait "$logcat_pid" >/dev/null 2>&1
fi
logcat_status=$?
set -e

if [ "$logcat_status" -ne 0 ] && [ "$logcat_status" -ne 124 ] && [ "$logcat_status" -ne 143 ]; then
  json_result "failed" "$LOG_PATH" "logcat capture failed before the QNN smoke window completed."
  exit 1
fi

missing=()
rejected=()

check_model() {
  local model="$1"
  grep -q "qnn_model_metadata model=$model " "$LOG_PATH" || missing+=("${model}_metadata")
  if grep -q "qnn_model_smoke status=loaded model=$model .*backend=qnn_htp" "$LOG_PATH"; then
    return
  fi
  if grep -q "qnn_model_smoke status=failed model=$model " "$LOG_PATH"; then
    rejected+=("$model")
    return
  fi
  if grep -q "qnn_model_smoke status=unavailable model=$model " "$LOG_PATH"; then
    rejected+=("$model")
    return
  fi
  missing+=("${model}_qnn_result")
}

if [ "$require_yolo" = "1" ]; then
  check_model "yolo"
fi
if [ "$require_depth" = "1" ]; then
  check_model "depth"
fi

if [ "${#missing[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "Missing expected QNN smoke evidence: ${missing[*]}."
  exit 1
fi

if [ "$REQUIRE_QNN_SUCCESS" = "1" ] && [ "${#rejected[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "QNN delegate rejected model(s): ${rejected[*]}."
  exit 1
fi

json_result "passed" "$LOG_PATH" "QNN smoke evidence captured for requested model(s)."
