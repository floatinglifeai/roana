#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${APP_ID:-com.roana.app}"
ACTIVITY="${ACTIVITY:-$APP_ID/.MainActivity}"
APK_PATH="${APK_PATH:-$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk}"
LOG_SECONDS="${LOG_SECONDS:-30}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
DEVICE_APK_PATH="${DEVICE_APK_PATH:-/data/local/tmp/roana-v0a-debug.apk}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="$LOG_DIR/v0a-device-$TIMESTAMP.log"

json_result() {
  local status="$1"
  local artifact="$2"
  local decision="$3"
  cat <<JSON
{
  "status": "$status",
  "hypothesis": "V0a Android skeleton runs on a connected real device",
  "artifact": "$artifact",
  "decision": "$decision"
}
JSON
}

install_apk() {
  local output_file
  local install_status
  output_file="$(mktemp)"

  adb "${DEVICE_ARG[@]}" push "$APK_PATH" "$DEVICE_APK_PATH" >/dev/null

  set +e
  adb "${DEVICE_ARG[@]}" shell pm install -r -g -d "$DEVICE_APK_PATH" >"$output_file" 2>&1
  install_status=$?
  set -e

  if [ "$install_status" -ne 0 ] && grep -q "INSTALL_FAILED_UPDATE_INCOMPATIBLE" "$output_file"; then
    adb "${DEVICE_ARG[@]}" uninstall "$APP_ID" >/dev/null 2>&1 || true
    set +e
    adb "${DEVICE_ARG[@]}" shell pm install -r -g -d "$DEVICE_APK_PATH" >"$output_file" 2>&1
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

if ! command -v adb >/dev/null 2>&1; then
  json_result "failed" "" "Install host adb before running the V0a device gate."
  exit 1
fi

mapfile -t devices < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')

if [ -n "${ANDROID_SERIAL:-}" ]; then
  DEVICE_ARG=(-s "$ANDROID_SERIAL")
elif [ "${#devices[@]}" -eq 1 ]; then
  DEVICE_ARG=(-s "${devices[0]}")
elif [ "${#devices[@]}" -eq 0 ]; then
  json_result "blocked" "" "Connect one Android 12+ arm64 phone with USB debugging enabled, or set ANDROID_SERIAL for wireless ADB."
  exit 2
else
  json_result "blocked" "" "Multiple ADB devices are connected; set ANDROID_SERIAL to choose one."
  exit 2
fi

if [ "${BUILD_FIRST:-1}" = "1" ] || [ ! -f "$APK_PATH" ]; then
  "$ROOT_DIR/scripts/build-debug.sh" >/dev/null
fi

if [ ! -f "$APK_PATH" ]; then
  json_result "failed" "" "Debug APK is missing after build."
  exit 1
fi

mkdir -p "$LOG_DIR"

if ! install_apk; then
  json_result "failed" "" "APK install failed through device-local pm install."
  exit 1
fi
adb "${DEVICE_ARG[@]}" shell pm grant "$APP_ID" android.permission.CAMERA >/dev/null 2>&1 || true
adb "${DEVICE_ARG[@]}" shell am force-stop "$APP_ID" >/dev/null 2>&1 || true
adb "${DEVICE_ARG[@]}" logcat -c >/dev/null
adb "${DEVICE_ARG[@]}" shell am start -n "$ACTIVITY" >/dev/null

set +e
timeout "${LOG_SECONDS}s" adb "${DEVICE_ARG[@]}" logcat -v time RoanaV0a:I '*:S' >"$LOG_PATH"
logcat_status=$?
set -e

if [ "$logcat_status" -ne 0 ] && [ "$logcat_status" -ne 124 ]; then
  json_result "failed" "$LOG_PATH" "logcat capture failed before the V0a evidence window completed."
  exit 1
fi

missing=()
grep -q "camera_bound" "$LOG_PATH" || missing+=("camera_bound")
grep -q "frame_stats" "$LOG_PATH" || missing+=("frame_stats")
grep -q "tts_event" "$LOG_PATH" || missing+=("tts_event")

if [ "${#missing[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "Missing expected RoanaV0a log evidence: ${missing[*]}."
  exit 1
fi

json_result "passed" "$LOG_PATH" "Real-device V0a skeleton proof exists; continue to YOLO CPU/XNNPACK inference."
