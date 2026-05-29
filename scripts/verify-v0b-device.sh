#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_SECONDS="${LOG_SECONDS:-90}"
MIN_DEPTH_FPS="${MIN_DEPTH_FPS:-10}"
REQUIRE_TARGET_SOC="${REQUIRE_TARGET_SOC:-1}"
REQUIRE_FP16_HTP="${REQUIRE_FP16_HTP:-1}"
REQUIRE_THERMAL_MINUTES="${REQUIRE_THERMAL_MINUTES:-30}"
RUN_THERMAL_GATE="${RUN_THERMAL_GATE:-0}"
REQUIRE_CORRIDOR_TEST="${REQUIRE_CORRIDOR_TEST:-1}"
CORRIDOR_TEST_RESULT="${CORRIDOR_TEST_RESULT:-}"
CORRIDOR_TEST_NOTES="${CORRIDOR_TEST_NOTES:-}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RESULT_DIR="${RESULT_DIR:-$ROOT_DIR/logs}"
RESULT_PATH="$RESULT_DIR/v0b-device-$TIMESTAMP.json"

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.stdin.read().strip()))'
}

json_result() {
  local status="$1"
  local artifact="$2"
  local decision="$3"
  local details="$4"
  mkdir -p "$RESULT_DIR"
  cat >"$RESULT_PATH" <<JSON
{
  "status": "$status",
  "hypothesis": "V0b corridor demo reaches the documented real-device safety and performance gates",
  "artifact": "$artifact",
  "decision": "$decision",
  "details": $details
}
JSON
  cat "$RESULT_PATH"
}

thermal_status() {
  adb "${DEVICE_ARG[@]}" shell dumpsys thermalservice 2>/dev/null |
    tr -d '\r' |
    awk '
      /Thermal Status:/ { status=$0 }
      /mStatus=/ { status=$0 }
      /Temperature/ && samples < 3 { sample = sample (sample ? " | " : "") $0; samples += 1 }
      END {
        if (status || sample) {
          print status (sample ? " | " sample : "")
        } else {
          print "unavailable"
        }
      }
    ' |
    tr '\n' ' '
}

analyze_log() {
  local log_path="$1"
  local thermal_log_path="${2:-}"
  local args=(
    "$ROOT_DIR/scripts/analyze-v0b-log.py"
    --log "$log_path"
    --model "$model"
    --soc-model "$soc_model"
    --board-platform "$board_platform"
    --abis "$abis"
    --min-depth-fps "$MIN_DEPTH_FPS"
    --require-target-soc "$REQUIRE_TARGET_SOC"
    --require-fp16-htp "$REQUIRE_FP16_HTP"
    --require-corridor-feedback "1"
    --thermal-minutes-required "$REQUIRE_THERMAL_MINUTES"
    --require-corridor-test "$REQUIRE_CORRIDOR_TEST"
    --corridor-test-result "$CORRIDOR_TEST_RESULT"
    --corridor-test-notes "$CORRIDOR_TEST_NOTES"
  )
  if [ -n "$thermal_log_path" ]; then
    args+=(
      --thermal-log "$thermal_log_path"
      --thermal-status-before "$thermal_status_before"
      --thermal-status-after "$thermal_status_after"
    )
  fi
  "${args[@]}"
}

analysis_details() {
  printf '%s' "$1" | python3 -c 'import json, sys; print(json.dumps(json.load(sys.stdin)["details"]))'
}

analysis_list_count() {
  local key="$1"
  printf '%s' "$2" | python3 -c 'import json, sys; print(len(json.load(sys.stdin)[sys.argv[1]]))' "$key"
}

analysis_list_text() {
  local key="$1"
  printf '%s' "$2" | python3 -c 'import json, sys; print(" ".join(json.load(sys.stdin)[sys.argv[1]]))' "$key"
}

if ! command -v adb >/dev/null 2>&1; then
  json_result "failed" "" "Install host adb before running the V0b device gate." "{}"
  exit 1
fi

mapfile -t devices < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')
if [ -n "${ANDROID_SERIAL:-}" ]; then
  DEVICE_ARG=(-s "$ANDROID_SERIAL")
elif [ "${#devices[@]}" -eq 1 ]; then
  DEVICE_ARG=(-s "${devices[0]}")
elif [ "${#devices[@]}" -eq 0 ]; then
  json_result "blocked" "" "Connect a Snapdragon 8 Gen 2+ / Dimensity 9300+ Android phone with USB debugging enabled." "{}"
  exit 2
else
  json_result "blocked" "" "Multiple ADB devices are connected; set ANDROID_SERIAL to choose one." "{}"
  exit 2
fi

model="$(adb "${DEVICE_ARG[@]}" shell getprop ro.product.model | tr -d '\r')"
soc_model="$(adb "${DEVICE_ARG[@]}" shell getprop ro.soc.model | tr -d '\r')"
board_platform="$(adb "${DEVICE_ARG[@]}" shell getprop ro.board.platform | tr -d '\r')"
abis="$(adb "${DEVICE_ARG[@]}" shell getprop ro.product.cpu.abilist | tr -d '\r')"

set +e
verify_output="$(
  REQUIRE_BACKEND=1 \
  REQUIRE_LIVE_CORRIDOR=1 \
  REQUIRE_CORRIDOR_FEEDBACK=1 \
  LOG_SECONDS="$LOG_SECONDS" \
  BUILD_FIRST="${BUILD_FIRST:-0}" \
  "$ROOT_DIR/scripts/verify-v0a-device.sh" 2>&1
)"
verify_status=$?
set -e

if [ "$verify_status" -ne 0 ]; then
  escaped_output="$(printf '%s' "$verify_output" | json_escape)"
  json_result "failed" "" "V0a depth-plan prerequisite gate failed." "{\"verify_output\": $escaped_output}"
  exit 1
fi

log_path="$(printf '%s\n' "$verify_output" | python3 -c 'import json, sys; print(json.load(sys.stdin)["artifact"])')"
if [ ! -f "$log_path" ]; then
  escaped_output="$(printf '%s' "$verify_output" | json_escape)"
  json_result "failed" "" "V0a verifier did not produce a readable log artifact." "{\"verify_output\": $escaped_output}"
  exit 1
fi

analysis_json="$(analyze_log "$log_path")"
details="$(analysis_details "$analysis_json")"
missing_count="$(analysis_list_count "missing" "$analysis_json")"
missing_text="$(analysis_list_text "missing" "$analysis_json")"
thermal_gate_run=false
thermal_log_path=""
thermal_status_before=""
thermal_status_after=""

if [ "$missing_count" -gt 0 ]; then
  json_result "failed" "$log_path" "V0b gate failed: $missing_text." "$details"
  exit 1
fi

if [ "$REQUIRE_THERMAL_MINUTES" -gt 0 ] && [ "$RUN_THERMAL_GATE" != "1" ]; then
  json_result "blocked" "$log_path" "Depth FPS prerequisites passed, but the ${REQUIRE_THERMAL_MINUTES}-minute thermal corridor gate still needs to be run with a sighted spotter." "$details"
  exit 2
fi

if [ "$REQUIRE_THERMAL_MINUTES" -gt 0 ]; then
  thermal_seconds=$((REQUIRE_THERMAL_MINUTES * 60))
  thermal_status_before="$(thermal_status)"

  set +e
  thermal_output="$(
    REQUIRE_BACKEND=1 \
    REQUIRE_LIVE_CORRIDOR=1 \
    REQUIRE_CORRIDOR_FEEDBACK=0 \
    REQUIRE_PERSON_TTS=0 \
    LOG_SECONDS="$thermal_seconds" \
    BUILD_FIRST=0 \
    "$ROOT_DIR/scripts/verify-v0a-device.sh" 2>&1
  )"
  thermal_status_code=$?
  set -e

  thermal_status_after="$(thermal_status)"
  if [ "$thermal_status_code" -ne 0 ]; then
    escaped_output="$(printf '%s' "$thermal_output" | json_escape)"
    json_result "failed" "$log_path" "Thermal corridor gate failed before the ${REQUIRE_THERMAL_MINUTES}-minute window completed." "{\"verify_output\": $escaped_output, \"prerequisite_details\": $details}"
    exit 1
  fi

  thermal_log_path="$(printf '%s\n' "$thermal_output" | python3 -c 'import json, sys; print(json.load(sys.stdin)["artifact"])')"
  if [ ! -f "$thermal_log_path" ]; then
    escaped_output="$(printf '%s' "$thermal_output" | json_escape)"
    json_result "failed" "$log_path" "Thermal verifier did not produce a readable log artifact." "{\"verify_output\": $escaped_output, \"prerequisite_details\": $details}"
    exit 1
  fi

  analysis_json="$(analyze_log "$log_path" "$thermal_log_path")"
  details="$(analysis_details "$analysis_json")"
  thermal_missing_count="$(analysis_list_count "thermal_missing" "$analysis_json")"
  thermal_missing_text="$(analysis_list_text "thermal_missing" "$analysis_json")"

  if [ "$thermal_missing_count" -gt 0 ]; then
    json_result "failed" "$thermal_log_path" "Thermal corridor gate failed: $thermal_missing_text." "$details"
    exit 1
  fi
fi

if [ "$REQUIRE_CORRIDOR_TEST" = "1" ] && [ "$CORRIDOR_TEST_RESULT" != "passed" ]; then
  json_result "blocked" "$log_path" "Machine gates passed, but known-corridor blindfold test evidence is still required. Set CORRIDOR_TEST_RESULT=passed after a sighted-spotter run." "$details"
  exit 2
fi

json_result "passed" "$log_path" "V0b device, thermal, and known-corridor sighted-spotter gates passed." "$details"
