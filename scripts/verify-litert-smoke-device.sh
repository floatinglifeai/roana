#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${APP_ID:-com.roana.litertsmoke}"
ACTIVITY="${ACTIVITY:-$APP_ID/.LiteRtSmokeActivity}"
APK_PATH="${APK_PATH:-$ROOT_DIR/litert-smoke/build/outputs/apk/debug/litert-smoke-debug.apk}"
LOG_SECONDS="${LOG_SECONDS:-30}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
MODEL="${MODEL:-all}"
LITERT_ACCELERATOR="${LITERT_ACCELERATOR:-npu}"
LITERT_NPU_PROVIDER="${LITERT_NPU_PROVIDER:-qualcomm}"
LITERT_QUALCOMM_OPTIONS="${LITERT_QUALCOMM_OPTIONS:-full}"
LITERT_TIMING_ITERATIONS="${LITERT_TIMING_ITERATIONS:-0}"
REQUIRE_LITERT_SUCCESS="${REQUIRE_LITERT_SUCCESS:-1}"
CAPTURE_FULL_LOGCAT="${CAPTURE_FULL_LOGCAT:-1}"
INSTALL_FIRST="${INSTALL_FIRST:-1}"
ADB_BIN="${ADB_BIN:-}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="$LOG_DIR/litert-smoke-$TIMESTAMP.log"
DEBUG_LITERT_YOLO_EXTRA="com.roana.app.extra.DEBUG_LITERT_YOLO_SMOKE"
DEBUG_LITERT_YOLO_AOT_EXTRA="com.roana.app.extra.DEBUG_LITERT_YOLO_AOT_SMOKE"
DEBUG_LITERT_DEPTH_EXTRA="com.roana.app.extra.DEBUG_LITERT_DEPTH_SMOKE"
DEBUG_LITERT_DEPTH_AOT_EXTRA="com.roana.app.extra.DEBUG_LITERT_DEPTH_AOT_SMOKE"
DEBUG_LITERT_EFFICIENTDET_EXTRA="com.roana.app.extra.DEBUG_LITERT_EFFICIENTDET_SMOKE"
DEBUG_LITERT_EFFICIENTDET_AOT_EXTRA="com.roana.app.extra.DEBUG_LITERT_EFFICIENTDET_AOT_SMOKE"
DEBUG_LITERT_ACCELERATOR_EXTRA="com.roana.app.extra.DEBUG_LITERT_ACCELERATOR"
DEBUG_LITERT_NPU_PROVIDER_EXTRA="com.roana.app.extra.DEBUG_LITERT_NPU_PROVIDER"
DEBUG_LITERT_QUALCOMM_OPTIONS_EXTRA="com.roana.app.extra.DEBUG_LITERT_QUALCOMM_OPTIONS"
DEBUG_LITERT_TIMING_ITERATIONS_EXTRA="com.roana.app.extra.DEBUG_LITERT_TIMING_ITERATIONS"
YOLO_AOT_ASSET="yolo11n-det-int8-smart_Qualcomm_SM8550.tflite"
DEPTH_AOT_ASSET="depth_anything_v2_Qualcomm_SM8550.tflite"
EFFICIENTDET_AOT_ASSET="efficientdet_lite0_detection_Qualcomm_SM8550.tflite"

json_result() {
  local status="$1"
  local artifact="$2"
  local decision="$3"
  cat <<JSON
{
  "status": "$status",
  "hypothesis": "LiteRT CompiledModel can be diagnosed independently for YOLO and Depth Anything with no silent CPU fallback",
  "artifact": "$artifact",
  "accelerator": "$LITERT_ACCELERATOR",
  "npu_provider": "$LITERT_NPU_PROVIDER",
  "qualcomm_options": "$LITERT_QUALCOMM_OPTIONS",
  "timing_iterations": $LITERT_TIMING_ITERATIONS,
  "decision": "$decision"
}
JSON
}

native_analysis_summary() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'native LiteRT log analysis unavailable because python3 is missing'
    return
  fi
  if [ ! -f "$ROOT_DIR/scripts/analyze-litert-smoke-log.py" ]; then
    printf 'native LiteRT log analysis unavailable because analyzer script is missing'
    return
  fi
  python3 - "$ROOT_DIR/scripts/analyze-litert-smoke-log.py" "$LOG_PATH" <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("litert_log_analyzer", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
result = module.analyze(Path(sys.argv[2]))
print(f'{result["status"]}: {result["decision"]}')
PY
}

native_analysis_status() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'unavailable'
    return
  fi
  if [ ! -f "$ROOT_DIR/scripts/analyze-litert-smoke-log.py" ]; then
    printf 'unavailable'
    return
  fi
  python3 - "$ROOT_DIR/scripts/analyze-litert-smoke-log.py" "$LOG_PATH" <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("litert_log_analyzer", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
result = module.analyze(Path(sys.argv[2]))
print(result["status"])
PY
}

native_analysis_proves_litert_npu() {
  local status
  status="$(native_analysis_status)"
  case "$status" in
    npu_log_evidence_present | npu_runtime_execution_evidence_present | aot_accelerator_execute_evidence_present)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

native_next_checks_summary() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'native LiteRT next-check planning unavailable because python3 is missing'
    return
  fi
  if [ ! -f "$ROOT_DIR/scripts/plan-litert-next-checks.py" ]; then
    printf 'native LiteRT next-check planning unavailable because planner script is missing'
    return
  fi
  python3 - "$ROOT_DIR/scripts/plan-litert-next-checks.py" "$LOG_PATH" <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("litert_next_checks", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
root = Path(sys.argv[1]).resolve().parents[1]
analyzer = module.load_analyzer(root)
result = module.plan_for(analyzer.analyze(Path(sys.argv[2])))
print("; ".join(result["next_checks"][:3]))
PY
}

apk_has_entry() {
  local entry="$1"
  local entries
  entries="$(unzip -Z1 "$APK_PATH")"
  printf '%s\n' "$entries" | grep -Fxq "$entry"
}

if [ -z "$ADB_BIN" ]; then
  if command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
  elif [ -x "$HOME/.local/android-platform-tools/platform-tools/adb" ]; then
    ADB_BIN="$HOME/.local/android-platform-tools/platform-tools/adb"
  fi
fi

if [ -z "$ADB_BIN" ]; then
  json_result "failed" "" "Install host adb before running the LiteRT smoke gate."
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
    require_yolo_aot=0
    require_depth=1
    require_depth_aot=0
    require_efficientdet=0
    require_efficientdet_aot=0
    ;;
  yolo)
    require_yolo=1
    require_yolo_aot=0
    require_depth=0
    require_depth_aot=0
    require_efficientdet=0
    require_efficientdet_aot=0
    ;;
  yolo_aot)
    require_yolo=0
    require_yolo_aot=1
    require_depth=0
    require_depth_aot=0
    require_efficientdet=0
    require_efficientdet_aot=0
    ;;
  depth)
    require_yolo=0
    require_yolo_aot=0
    require_depth=1
    require_depth_aot=0
    require_efficientdet=0
    require_efficientdet_aot=0
    ;;
  depth_aot)
    require_yolo=0
    require_yolo_aot=0
    require_depth=0
    require_depth_aot=1
    require_efficientdet=0
    require_efficientdet_aot=0
    ;;
  all_aot)
    require_yolo=0
    require_yolo_aot=1
    require_depth=0
    require_depth_aot=1
    require_efficientdet=0
    require_efficientdet_aot=0
    ;;
  efficientdet)
    require_yolo=0
    require_yolo_aot=0
    require_depth=0
    require_depth_aot=0
    require_efficientdet=1
    require_efficientdet_aot=0
    ;;
  efficientdet_aot)
    require_yolo=0
    require_yolo_aot=0
    require_depth=0
    require_depth_aot=0
    require_efficientdet=0
    require_efficientdet_aot=1
    ;;
  *)
    json_result "failed" "" "MODEL must be one of: all, yolo, yolo_aot, depth, depth_aot, all_aot, efficientdet, efficientdet_aot."
    exit 1
    ;;
esac

case "$LITERT_ACCELERATOR" in
  npu | gpu | cpu)
    ;;
  *)
    json_result "failed" "" "LITERT_ACCELERATOR must be one of: npu, gpu, cpu."
    exit 1
    ;;
esac

case "$LITERT_NPU_PROVIDER" in
  qualcomm | default | none)
    ;;
  *)
    json_result "failed" "" "LITERT_NPU_PROVIDER must be one of: qualcomm, default, none."
    exit 1
    ;;
esac

case "$LITERT_QUALCOMM_OPTIONS" in
  full | minimal | none)
    ;;
  *)
    json_result "failed" "" "LITERT_QUALCOMM_OPTIONS must be one of: full, minimal, none."
    exit 1
    ;;
esac

if [ "${BUILD_FIRST:-0}" = "1" ] || [ ! -f "$APK_PATH" ]; then
  "$ROOT_DIR/scripts/build-litert-smoke-debug.sh" >/dev/null
fi

if [ ! -f "$APK_PATH" ]; then
  json_result "failed" "" "Debug APK is missing after build."
  exit 1
fi

missing_aot_assets=()
if [ "$require_yolo_aot" = "1" ]; then
  apk_has_entry "assets/$YOLO_AOT_ASSET" || missing_aot_assets+=("$YOLO_AOT_ASSET")
fi
if [ "$require_depth_aot" = "1" ]; then
  apk_has_entry "assets/$DEPTH_AOT_ASSET" || missing_aot_assets+=("$DEPTH_AOT_ASSET")
fi
if [ "$require_efficientdet_aot" = "1" ]; then
  apk_has_entry "assets/$EFFICIENTDET_AOT_ASSET" || missing_aot_assets+=("$EFFICIENTDET_AOT_ASSET")
fi
if [ "${#missing_aot_assets[@]}" -gt 0 ]; then
  json_result "blocked" "" "Requested AOT model(s) require missing smoke APK assets: ${missing_aot_assets[*]}. Build with LITERT_EXTRA_ASSET_DIR pointing at the compiled SM8550 AOT asset directory."
  exit 2
fi

if [ "$INSTALL_FIRST" = "1" ]; then
  "$ADB_BIN" "${DEVICE_ARG[@]}" install -r "$APK_PATH" >/dev/null
fi

mkdir -p "$LOG_DIR"
"$ADB_BIN" "${DEVICE_ARG[@]}" shell am force-stop "$APP_ID" >/dev/null 2>&1 || true
"$ADB_BIN" "${DEVICE_ARG[@]}" logcat -c >/dev/null

start_args=(-n "$ACTIVITY")
start_args+=(--es "$DEBUG_LITERT_ACCELERATOR_EXTRA" "$LITERT_ACCELERATOR")
start_args+=(--es "$DEBUG_LITERT_NPU_PROVIDER_EXTRA" "$LITERT_NPU_PROVIDER")
start_args+=(--es "$DEBUG_LITERT_QUALCOMM_OPTIONS_EXTRA" "$LITERT_QUALCOMM_OPTIONS")
start_args+=(--ei "$DEBUG_LITERT_TIMING_ITERATIONS_EXTRA" "$LITERT_TIMING_ITERATIONS")
if [ "$require_yolo" = "1" ]; then
  start_args+=(--ez "$DEBUG_LITERT_YOLO_EXTRA" true)
fi
if [ "$require_yolo_aot" = "1" ]; then
  start_args+=(--ez "$DEBUG_LITERT_YOLO_AOT_EXTRA" true)
fi
if [ "$require_depth" = "1" ]; then
  start_args+=(--ez "$DEBUG_LITERT_DEPTH_EXTRA" true)
fi
if [ "$require_depth_aot" = "1" ]; then
  start_args+=(--ez "$DEBUG_LITERT_DEPTH_AOT_EXTRA" true)
fi
if [ "$require_efficientdet" = "1" ]; then
  start_args+=(--ez "$DEBUG_LITERT_EFFICIENTDET_EXTRA" true)
fi
if [ "$require_efficientdet_aot" = "1" ]; then
  start_args+=(--ez "$DEBUG_LITERT_EFFICIENTDET_AOT_EXTRA" true)
fi
"$ADB_BIN" "${DEVICE_ARG[@]}" shell am start "${start_args[@]}" >/dev/null

set +e
if [ "$CAPTURE_FULL_LOGCAT" = "1" ]; then
  logcat_args=(logcat -v time)
else
  logcat_args=(logcat -v time RoanaLiteRt:I '*:S')
fi

if command -v timeout >/dev/null 2>&1; then
  timeout "${LOG_SECONDS}s" "$ADB_BIN" "${DEVICE_ARG[@]}" "${logcat_args[@]}" >"$LOG_PATH"
else
  "$ADB_BIN" "${DEVICE_ARG[@]}" "${logcat_args[@]}" >"$LOG_PATH" &
  logcat_pid=$!
  sleep "$LOG_SECONDS"
  kill "$logcat_pid" >/dev/null 2>&1 || true
  wait "$logcat_pid" >/dev/null 2>&1
fi
logcat_status=$?
set -e

if [ "$logcat_status" -ne 0 ] && [ "$logcat_status" -ne 124 ] && [ "$logcat_status" -ne 143 ]; then
  json_result "failed" "$LOG_PATH" "logcat capture failed before the LiteRT smoke window completed."
  exit 1
fi

missing=()
failed=()
unavailable=()
unproven=()
runtime_missing=()
rejected=()

check_model() {
  local model="$1"
  grep -q "litert_model_metadata model=$model " "$LOG_PATH" || missing+=("${model}_metadata")
  grep -q "litert_backend requested=$LITERT_ACCELERATOR model=$model " "$LOG_PATH" ||
    missing+=("${model}_backend_request")

  if grep -q "litert_backend status=unproven model=$model " "$LOG_PATH" ||
    grep -q "litert_model_smoke status=loaded model=$model .*backend=unproven " "$LOG_PATH"; then
    unproven+=("$model")
    return
  fi
  if grep -q "litert_model_smoke status=loaded model=$model .*backend=$LITERT_ACCELERATOR" "$LOG_PATH"; then
    if [ "$LITERT_TIMING_ITERATIONS" -gt 0 ] &&
      ! grep -q "litert_model_timing status=ok model=$model backend=$LITERT_ACCELERATOR " "$LOG_PATH"; then
      missing+=("${model}_timing")
    fi
    return
  fi

  if grep -q "litert_backend selected=unavailable model=$model " "$LOG_PATH"; then
    unavailable+=("$model")
    return
  fi
  if grep -q "litert_model_smoke status=failed model=$model .*backend=missing " "$LOG_PATH" ||
    grep -q "litert_runtime status=missing model=$model " "$LOG_PATH"; then
    runtime_missing+=("$model")
    return
  fi
  if grep -q "litert_model_smoke status=failed model=$model .*reason=model_rejected" "$LOG_PATH" ||
    grep -q "litert_model status=rejected model=$model " "$LOG_PATH"; then
    rejected+=("$model")
    return
  fi
  if grep -q "litert_model_smoke status=failed model=$model .*backend=unproven " "$LOG_PATH"; then
    unproven+=("$model")
    return
  fi
  if grep -q "litert_model_smoke status=failed model=$model " "$LOG_PATH"; then
    failed+=("$model")
    return
  fi

  missing+=("${model}_litert_result")
}

if [ "$require_yolo" = "1" ]; then
  check_model "yolo"
fi
if [ "$require_yolo_aot" = "1" ]; then
  check_model "yolo_aot"
fi
if [ "$require_depth" = "1" ]; then
  check_model "depth"
fi
if [ "$require_depth_aot" = "1" ]; then
  check_model "depth_aot"
fi
if [ "$require_efficientdet" = "1" ]; then
  check_model "efficientdet"
fi
if [ "$require_efficientdet_aot" = "1" ]; then
  check_model "efficientdet_aot"
fi

if [ "${#missing[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "Missing expected LiteRT smoke evidence: ${missing[*]}."
  exit 1
fi

if [ "$REQUIRE_LITERT_SUCCESS" = "1" ] && [ "${#runtime_missing[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "LiteRT runtime missing for model(s): ${runtime_missing[*]}."
  exit 1
fi

if [ "$REQUIRE_LITERT_SUCCESS" = "1" ] && [ "${#rejected[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "LiteRT rejected model(s): ${rejected[*]}."
  exit 1
fi

if [ "$REQUIRE_LITERT_SUCCESS" = "1" ] && [ "${#unavailable[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "LiteRT accelerator unavailable for model(s): ${unavailable[*]}."
  exit 1
fi

if [ "$REQUIRE_LITERT_SUCCESS" = "1" ] && [ "${#unproven[@]}" -gt 0 ]; then
  if [ "$LITERT_ACCELERATOR" = "npu" ] && native_analysis_proves_litert_npu; then
    json_result "passed" "$LOG_PATH" "LiteRT Java backend label is unproven for model(s): ${unproven[*]}, but native smoke-PID QNN execution evidence was captured. Native analysis: $(native_analysis_summary)."
    exit 0
  fi
  json_result "failed" "$LOG_PATH" "LiteRT backend proof unproven for model(s): ${unproven[*]}. Native analysis: $(native_analysis_summary). Next checks: $(native_next_checks_summary)."
  exit 1
fi

if [ "$REQUIRE_LITERT_SUCCESS" = "1" ] && [ "${#failed[@]}" -gt 0 ]; then
  json_result "failed" "$LOG_PATH" "LiteRT smoke failed for model(s): ${failed[*]}. Native analysis: $(native_analysis_summary). Next checks: $(native_next_checks_summary)."
  exit 1
fi

json_result "passed" "$LOG_PATH" "LiteRT smoke evidence captured for requested model(s) with requested accelerator."
