#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${APP_ID:-com.roana.app}"
ACTIVITY="${ACTIVITY:-$APP_ID/.MainActivity}"
APK_PATH="${APK_PATH:-$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk}"
LOG_SECONDS="${LOG_SECONDS:-30}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
DEVICE_APK_PATH="${DEVICE_APK_PATH:-/data/local/tmp/roana-v0a-debug.apk}"
REQUIRE_YOLO="${REQUIRE_YOLO:-1}"
REQUIRE_PERSON_TTS="${REQUIRE_PERSON_TTS:-1}"
REQUIRE_BACKEND="${REQUIRE_BACKEND:-0}"
REQUIRE_DEPTH_SMOKE="${REQUIRE_DEPTH_SMOKE:-0}"
REQUIRE_DEPTH_PLAN="${REQUIRE_DEPTH_PLAN:-0}"
REQUIRE_LIVE_CORRIDOR="${REQUIRE_LIVE_CORRIDOR:-0}"
REQUIRE_CORRIDOR_FEEDBACK="${REQUIRE_CORRIDOR_FEEDBACK:-$REQUIRE_DEPTH_PLAN}"
REQUIRE_SAFE_STOP="${REQUIRE_SAFE_STOP:-0}"
DEBUG_PERSON_EXTRA="com.roana.app.extra.DEBUG_PERSON_DETECTION"
DEBUG_DEPTH_EXTRA="com.roana.app.extra.DEBUG_DEPTH_SMOKE"
DEBUG_DEPTH_PLAN_EXTRA="com.roana.app.extra.DEBUG_DEPTH_PLAN"
DEBUG_LIVE_CORRIDOR_EXTRA="com.roana.app.extra.DEBUG_LIVE_CORRIDOR"
DEBUG_SAFE_STOP_EXTRA="com.roana.app.extra.DEBUG_SAFE_STOP"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="$LOG_DIR/v0a-device-$TIMESTAMP.log"

json_result() {
  local status="$1"
  local artifact="$2"
  local decision="$3"
  cat <<JSON
{
  "status": "$status",
  "hypothesis": "V0a Android CameraX/TFLite/detection-to-TTS loop runs on a connected real device",
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
start_args=(-n "$ACTIVITY")
if [ "$REQUIRE_PERSON_TTS" = "1" ]; then
  start_args+=(--ez "$DEBUG_PERSON_EXTRA" true)
fi
if [ "$REQUIRE_DEPTH_SMOKE" = "1" ]; then
  start_args+=(--ez "$DEBUG_DEPTH_EXTRA" true)
fi
if [ "$REQUIRE_DEPTH_PLAN" = "1" ]; then
  start_args+=(--ez "$DEBUG_DEPTH_EXTRA" true --ez "$DEBUG_DEPTH_PLAN_EXTRA" true)
fi
if [ "$REQUIRE_LIVE_CORRIDOR" = "1" ]; then
  start_args+=(--ez "$DEBUG_LIVE_CORRIDOR_EXTRA" true)
fi
if [ "$REQUIRE_SAFE_STOP" = "1" ]; then
  start_args+=(--ez "$DEBUG_SAFE_STOP_EXTRA" true)
fi
adb "${DEVICE_ARG[@]}" shell am start "${start_args[@]}" >/dev/null

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
if [ "$REQUIRE_YOLO" = "1" ]; then
  frame_count="$(grep -c "frame_stats" "$LOG_PATH" || true)"
  [ "$frame_count" -ge 5 ] || missing+=("frame_stats>=5")
  grep -q "yolo_inference" "$LOG_PATH" || missing+=("yolo_inference")
  grep -q "inference_ms=" "$LOG_PATH" || missing+=("inference_ms")
  grep -q "detection=" "$LOG_PATH" || missing+=("detection_status")
  ! grep -q "yolo_error" "$LOG_PATH" || missing+=("no_yolo_error")
fi
if [ "$REQUIRE_PERSON_TTS" = "1" ]; then
  grep -q "debug_person_detection_proof" "$LOG_PATH" || missing+=("debug_person_detection_proof")
  grep -q "message=person_ahead" "$LOG_PATH" || missing+=("person_ahead_tts")
fi
if [ "$REQUIRE_BACKEND" = "1" ]; then
  grep -q "qnn_probe" "$LOG_PATH" || missing+=("qnn_probe")
  grep -q "qnn_capabilities" "$LOG_PATH" || missing+=("qnn_capabilities")
  grep -q "inference_backend selected=" "$LOG_PATH" || missing+=("inference_backend")
  if ! grep -q "inference_backend selected=qnn_htp" "$LOG_PATH" &&
    ! grep -q "reason=qnn_interpreter_failed" "$LOG_PATH" &&
    ! grep -q "reason=qnn_create_failed" "$LOG_PATH"; then
    missing+=("backend_success_or_fallback")
  fi
fi
if [ "$REQUIRE_DEPTH_SMOKE" = "1" ]; then
  grep -q "qnn_probe precision=fp16" "$LOG_PATH" || missing+=("depth_qnn_probe")
  grep -q "depth_smoke status=loaded" "$LOG_PATH" || missing+=("depth_smoke_loaded")
  ! grep -q "depth_smoke status=failed" "$LOG_PATH" || missing+=("no_depth_smoke_failed")
fi
if [ "$REQUIRE_DEPTH_PLAN" = "1" ]; then
  grep -q "depth_plan status=ok" "$LOG_PATH" || missing+=("depth_plan_ok")
fi
if [ "$REQUIRE_LIVE_CORRIDOR" = "1" ]; then
  grep -q "corridor_live enabled=true" "$LOG_PATH" || missing+=("corridor_live_enabled")
  grep -q "corridor_live status=ok" "$LOG_PATH" || missing+=("corridor_live_ok")
  ! grep -q "corridor_live status=failed" "$LOG_PATH" || missing+=("no_corridor_live_failed")
fi
if [ "$REQUIRE_CORRIDOR_FEEDBACK" = "1" ]; then
  grep -q "corridor_feedback status=spoken" "$LOG_PATH" || missing+=("corridor_feedback_spoken")
  grep -q "id=roana-corridor-" "$LOG_PATH" || missing+=("corridor_feedback_utterance")
fi
if [ "$REQUIRE_SAFE_STOP" = "1" ]; then
  grep -q "debug_safe_stop_proof enabled=true reason=low_confidence decision=STOP state=STOP" "$LOG_PATH" ||
    missing+=("debug_safe_stop_proof")
  grep -q "corridor_feedback status=spoken .*command=STOP .*message=stop reason=low_confidence" "$LOG_PATH" ||
    missing+=("safe_stop_feedback")
fi

if [ "${#missing[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "Missing expected RoanaV0a log evidence: ${missing[*]}."
  exit 1
fi

json_result "passed" "$LOG_PATH" "Real-device V0a CameraX/TFLite/detection-to-TTS proof exists."
