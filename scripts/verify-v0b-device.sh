#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_SECONDS="${LOG_SECONDS:-90}"
MIN_DEPTH_FPS="${MIN_DEPTH_FPS:-10}"
MAX_DEPTH_MS="$(awk -v fps="$MIN_DEPTH_FPS" 'BEGIN { printf "%.2f", 1000 / fps }')"
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

mean_depth_ms() {
  local log_path="$1"
  grep "corridor_live status=ok" "$log_path" | sed -n 's/.*depth_ms=\([0-9.]*\).*/\1/p' | awk '
    { sum += $1; count += 1 }
    END { if (count > 0) printf "%.2f", sum / count }
  '
}

tail_mean_depth_ms() {
  local log_path="$1"
  local sample_count="$2"
  grep "corridor_live status=ok" "$log_path" |
    tail -n "$sample_count" |
    sed -n 's/.*depth_ms=\([0-9.]*\).*/\1/p' |
    awk '
      { sum += $1; count += 1 }
      END { if (count > 0) printf "%.2f", sum / count }
    '
}

fps_from_ms() {
  local elapsed_ms="$1"
  awk -v ms="${elapsed_ms:-0}" 'BEGIN { if (ms > 0) printf "%.3f", 1000 / ms; else printf "0" }'
}

last_gap_count() {
  local log_path="$1"
  local value
  value="$(grep "frame_stats" "$log_path" | tail -1 | sed -n 's/.*gap_count=\([0-9]*\).*/\1/p')"
  printf '%s' "${value:-0}"
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

target_soc=0
case "${soc_model,,} ${board_platform,,}" in
  *"sm8550"*|*"sm8650"*|*"sm8750"*|*"sm8850"*|*"dimensity 9300"*|*"dimensity 9400"*)
    target_soc=1
    ;;
esac

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

fp16_htp="$(grep -m1 "qnn_capabilities" "$log_path" | sed -n 's/.*htp_fp16=\([^ ]*\).*/\1/p')"
depth_elapsed_ms="$(mean_depth_ms "$log_path")"
if [ -z "$depth_elapsed_ms" ]; then
  depth_elapsed_ms="$(grep -m1 "depth_plan status=ok" "$log_path" | sed -n 's/.*elapsed_ms=\([0-9.]*\).*/\1/p')"
fi
corridor_feedback="$(grep -m1 "corridor_feedback status=spoken" "$log_path" || true)"
live_corridor_count="$(grep -c "corridor_live status=ok" "$log_path" || true)"
depth_fps="$(fps_from_ms "$depth_elapsed_ms")"
frame_stats_count="$(grep -c "frame_stats" "$log_path" || true)"
gap_count="$(last_gap_count "$log_path")"
thermal_gate_run=false
thermal_log_path=""
thermal_status_before=""
thermal_status_after=""
thermal_live_corridor_count=0
thermal_depth_elapsed_ms=0
thermal_depth_fps=0
thermal_tail_depth_elapsed_ms=0
thermal_tail_depth_fps=0
thermal_frame_stats_count=0
thermal_gap_count=0

missing=()
if [ "$REQUIRE_TARGET_SOC" = "1" ] && [ "$target_soc" -ne 1 ]; then
  missing+=("target_soc")
fi
if [ "$REQUIRE_FP16_HTP" = "1" ] && [ "$fp16_htp" != "true" ]; then
  missing+=("fp16_htp")
fi
awk -v actual="${depth_elapsed_ms:-999999}" -v max="$MAX_DEPTH_MS" 'BEGIN { exit actual <= max ? 0 : 1 }' ||
  missing+=("depth_fps>=${MIN_DEPTH_FPS}")
[ "$live_corridor_count" -ge 5 ] || missing+=("corridor_live_frames>=5")
[ "$frame_stats_count" -ge 5 ] || missing+=("frame_stats>=5")
[ "$gap_count" -eq 0 ] || missing+=("no_frame_gaps")

details="$(CORRIDOR_TEST_RESULT="$CORRIDOR_TEST_RESULT" CORRIDOR_TEST_NOTES="$CORRIDOR_TEST_NOTES" python3 - <<PY
import json
import os
print(json.dumps({
    "model": "$model",
    "soc_model": "$soc_model",
    "board_platform": "$board_platform",
    "abis": "$abis",
    "target_soc": bool($target_soc),
    "fp16_htp": "$fp16_htp",
    "depth_elapsed_ms": float("${depth_elapsed_ms:-0}"),
    "depth_fps": float("$depth_fps"),
    "corridor_feedback": "$corridor_feedback",
    "live_corridor_count": int("$live_corridor_count"),
    "min_depth_fps": float("$MIN_DEPTH_FPS"),
    "max_depth_ms": float("$MAX_DEPTH_MS"),
    "frame_stats_count": int("$frame_stats_count"),
    "gap_count": int("$gap_count"),
    "thermal_minutes_required": int("$REQUIRE_THERMAL_MINUTES"),
    "thermal_gate_run": "$thermal_gate_run" == "true",
    "thermal_log_path": "$thermal_log_path",
    "thermal_status_before": os.environ.get("THERMAL_STATUS_BEFORE", ""),
    "thermal_status_after": os.environ.get("THERMAL_STATUS_AFTER", ""),
    "thermal_live_corridor_count": int("$thermal_live_corridor_count"),
    "thermal_depth_elapsed_ms": float("$thermal_depth_elapsed_ms"),
    "thermal_depth_fps": float("$thermal_depth_fps"),
    "thermal_tail_depth_elapsed_ms": float("$thermal_tail_depth_elapsed_ms"),
    "thermal_tail_depth_fps": float("$thermal_tail_depth_fps"),
    "thermal_frame_stats_count": int("$thermal_frame_stats_count"),
    "thermal_gap_count": int("$thermal_gap_count"),
    "corridor_test_required": "$REQUIRE_CORRIDOR_TEST" == "1",
    "corridor_test_result": os.environ.get("CORRIDOR_TEST_RESULT", ""),
    "corridor_test_notes": os.environ.get("CORRIDOR_TEST_NOTES", ""),
    "log_path": "$log_path",
}))
PY
)"

if [ "${#missing[@]}" -gt 0 ]; then
  json_result "failed" "$log_path" "V0b gate failed: ${missing[*]}." "$details"
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

  thermal_live_corridor_count="$(grep -c "corridor_live status=ok" "$thermal_log_path" || true)"
  thermal_depth_elapsed_ms="$(mean_depth_ms "$thermal_log_path")"
  thermal_depth_fps="$(fps_from_ms "$thermal_depth_elapsed_ms")"
  thermal_tail_depth_elapsed_ms="$(tail_mean_depth_ms "$thermal_log_path" 20)"
  thermal_tail_depth_fps="$(fps_from_ms "$thermal_tail_depth_elapsed_ms")"
  thermal_frame_stats_count="$(grep -c "frame_stats" "$thermal_log_path" || true)"
  thermal_gap_count="$(last_gap_count "$thermal_log_path")"
  thermal_gate_run=true

  thermal_missing=()
  [ "$thermal_live_corridor_count" -ge "$((REQUIRE_THERMAL_MINUTES * 60))" ] ||
    thermal_missing+=("thermal_corridor_live_frames")
  awk -v actual="${thermal_depth_elapsed_ms:-999999}" -v max="$MAX_DEPTH_MS" 'BEGIN { exit actual <= max ? 0 : 1 }' ||
    thermal_missing+=("thermal_avg_depth_fps>=${MIN_DEPTH_FPS}")
  awk -v actual="${thermal_tail_depth_elapsed_ms:-999999}" -v max="$MAX_DEPTH_MS" 'BEGIN { exit actual <= max ? 0 : 1 }' ||
    thermal_missing+=("thermal_tail_depth_fps>=${MIN_DEPTH_FPS}")
  [ "$thermal_frame_stats_count" -ge "$REQUIRE_THERMAL_MINUTES" ] ||
    thermal_missing+=("thermal_frame_stats")
  [ "$thermal_gap_count" -eq 0 ] || thermal_missing+=("thermal_no_frame_gaps")

  details="$(CORRIDOR_TEST_RESULT="$CORRIDOR_TEST_RESULT" CORRIDOR_TEST_NOTES="$CORRIDOR_TEST_NOTES" THERMAL_STATUS_BEFORE="$thermal_status_before" THERMAL_STATUS_AFTER="$thermal_status_after" python3 - <<PY
import json
import os
print(json.dumps({
    "model": "$model",
    "soc_model": "$soc_model",
    "board_platform": "$board_platform",
    "abis": "$abis",
    "target_soc": bool($target_soc),
    "fp16_htp": "$fp16_htp",
    "depth_elapsed_ms": float("${depth_elapsed_ms:-0}"),
    "depth_fps": float("$depth_fps"),
    "corridor_feedback": "$corridor_feedback",
    "live_corridor_count": int("$live_corridor_count"),
    "min_depth_fps": float("$MIN_DEPTH_FPS"),
    "max_depth_ms": float("$MAX_DEPTH_MS"),
    "frame_stats_count": int("$frame_stats_count"),
    "gap_count": int("$gap_count"),
    "thermal_minutes_required": int("$REQUIRE_THERMAL_MINUTES"),
    "thermal_gate_run": "$thermal_gate_run" == "true",
    "thermal_log_path": "$thermal_log_path",
    "thermal_status_before": os.environ.get("THERMAL_STATUS_BEFORE", ""),
    "thermal_status_after": os.environ.get("THERMAL_STATUS_AFTER", ""),
    "thermal_live_corridor_count": int("$thermal_live_corridor_count"),
    "thermal_depth_elapsed_ms": float("${thermal_depth_elapsed_ms:-0}"),
    "thermal_depth_fps": float("$thermal_depth_fps"),
    "thermal_tail_depth_elapsed_ms": float("${thermal_tail_depth_elapsed_ms:-0}"),
    "thermal_tail_depth_fps": float("$thermal_tail_depth_fps"),
    "thermal_frame_stats_count": int("$thermal_frame_stats_count"),
    "thermal_gap_count": int("$thermal_gap_count"),
    "corridor_test_required": "$REQUIRE_CORRIDOR_TEST" == "1",
    "corridor_test_result": os.environ.get("CORRIDOR_TEST_RESULT", ""),
    "corridor_test_notes": os.environ.get("CORRIDOR_TEST_NOTES", ""),
    "log_path": "$log_path",
}))
PY
)"

  if [ "${#thermal_missing[@]}" -gt 0 ]; then
    json_result "failed" "$thermal_log_path" "Thermal corridor gate failed: ${thermal_missing[*]}." "$details"
    exit 1
  fi
fi

if [ "$REQUIRE_CORRIDOR_TEST" = "1" ] && [ "$CORRIDOR_TEST_RESULT" != "passed" ]; then
  details="$(CORRIDOR_TEST_RESULT="$CORRIDOR_TEST_RESULT" CORRIDOR_TEST_NOTES="$CORRIDOR_TEST_NOTES" THERMAL_STATUS_BEFORE="$thermal_status_before" THERMAL_STATUS_AFTER="$thermal_status_after" python3 - <<PY
import json
import os
print(json.dumps({
    "model": "$model",
    "soc_model": "$soc_model",
    "board_platform": "$board_platform",
    "abis": "$abis",
    "target_soc": bool($target_soc),
    "fp16_htp": "$fp16_htp",
    "depth_elapsed_ms": float("${depth_elapsed_ms:-0}"),
    "depth_fps": float("$depth_fps"),
    "corridor_feedback": "$corridor_feedback",
    "live_corridor_count": int("$live_corridor_count"),
    "min_depth_fps": float("$MIN_DEPTH_FPS"),
    "max_depth_ms": float("$MAX_DEPTH_MS"),
    "frame_stats_count": int("$frame_stats_count"),
    "gap_count": int("$gap_count"),
    "thermal_minutes_required": int("$REQUIRE_THERMAL_MINUTES"),
    "thermal_gate_run": "$thermal_gate_run" == "true",
    "thermal_log_path": "$thermal_log_path",
    "thermal_status_before": os.environ.get("THERMAL_STATUS_BEFORE", ""),
    "thermal_status_after": os.environ.get("THERMAL_STATUS_AFTER", ""),
    "thermal_live_corridor_count": int("$thermal_live_corridor_count"),
    "thermal_depth_elapsed_ms": float("${thermal_depth_elapsed_ms:-0}"),
    "thermal_depth_fps": float("$thermal_depth_fps"),
    "thermal_tail_depth_elapsed_ms": float("${thermal_tail_depth_elapsed_ms:-0}"),
    "thermal_tail_depth_fps": float("$thermal_tail_depth_fps"),
    "thermal_frame_stats_count": int("$thermal_frame_stats_count"),
    "thermal_gap_count": int("$thermal_gap_count"),
    "corridor_test_required": True,
    "corridor_test_result": os.environ.get("CORRIDOR_TEST_RESULT", ""),
    "corridor_test_notes": os.environ.get("CORRIDOR_TEST_NOTES", ""),
    "log_path": "$log_path",
}))
PY
)"
  json_result "blocked" "$log_path" "Machine gates passed, but known-corridor blindfold test evidence is still required. Set CORRIDOR_TEST_RESULT=passed after a sighted-spotter run." "$details"
  exit 2
fi

json_result "passed" "$log_path" "V0b device, thermal, and known-corridor sighted-spotter gates passed." "$details"
