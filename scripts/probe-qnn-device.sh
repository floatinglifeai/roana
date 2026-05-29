#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="${APP_ID:-com.roana.app}"
APK_PATH="${APK_PATH:-$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
LOG_SECONDS="${LOG_SECONDS:-12}"
MODEL="${MODEL:-all}"
QNN_VARIANTS="${QNN_VARIANTS:-default explicit_paths signed_pd signed_pd_explicit_paths default_perf_explicit_paths}"
ADB_BIN="${ADB_BIN:-}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_PATH="$LOG_DIR/qnn-probe-$TIMESTAMP.log"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_result() {
  local status="$1"
  local artifact="$2"
  local decision="$3"
  printf '{\n'
  printf '  "status": "%s",\n' "$(json_escape "$status")"
  printf '  "artifact": "%s",\n' "$(json_escape "$artifact")"
  printf '  "decision": "%s"\n' "$(json_escape "$decision")"
  printf '}\n'
}

append_section() {
  printf '\n== %s ==\n' "$1" >>"$LOG_PATH"
}

run_host() {
  printf '$ %s\n' "$*" >>"$LOG_PATH"
  "$@" >>"$LOG_PATH" 2>&1
  local status=$?
  printf '[exit=%s]\n' "$status" >>"$LOG_PATH"
  return "$status"
}

run_adb_shell() {
  printf '$ adb shell %s\n' "$*" >>"$LOG_PATH"
  "$ADB_BIN" "${DEVICE_ARG[@]}" shell "$@" >>"$LOG_PATH" 2>&1
  local status=$?
  printf '[exit=%s]\n' "$status" >>"$LOG_PATH"
  return "$status"
}

run_adb_sh() {
  printf '$ adb shell sh -c %s\n' "$1" >>"$LOG_PATH"
  "$ADB_BIN" "${DEVICE_ARG[@]}" shell sh -c "$1" >>"$LOG_PATH" 2>&1
  local status=$?
  printf '[exit=%s]\n' "$status" >>"$LOG_PATH"
  return "$status"
}

run_adb_script() {
  printf '$ adb shell sh <<SCRIPT\n%s\nSCRIPT\n' "$1" >>"$LOG_PATH"
  printf '%s\n' "$1" | "$ADB_BIN" "${DEVICE_ARG[@]}" shell sh >>"$LOG_PATH" 2>&1
  local status=$?
  printf '[exit=%s]\n' "$status" >>"$LOG_PATH"
  return "$status"
}

resolve_adb() {
  if [ -n "$ADB_BIN" ]; then
    return
  fi
  if command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
  elif [ -x "$HOME/.local/android-platform-tools/platform-tools/adb" ]; then
    ADB_BIN="$HOME/.local/android-platform-tools/platform-tools/adb"
  fi
}

select_device() {
  local devices=()
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
}

classify_artifact() {
  if grep -q "QNN DSP transport dependency missing from app linker namespace" "$LOG_PATH"; then
    json_result "failed" "$LOG_PATH" "QNN HTP stub is present, but libcdsprpc.so is not visible in the app linker namespace; next step should test dependency packaging/linker visibility before changing model export."
    exit 1
  fi
  if grep -q "QNN DSP transport/skeleton setup failed before model-specific offload" "$LOG_PATH"; then
    json_result "failed" "$LOG_PATH" "QNN DSP transport/skeleton setup still fails before model-specific offload; inspect package/layout evidence before backend migration."
    exit 1
  fi
  if grep -q "QNN delegate rejected model(s)" "$LOG_PATH"; then
    json_result "failed" "$LOG_PATH" "QNN transport appears to reach model delegation, but model compatibility is rejected."
    exit 1
  fi
  if grep -q '"status": "passed"' "$LOG_PATH"; then
    json_result "passed" "$LOG_PATH" "QNN smoke passed for requested model(s); rerun V0b gate."
    exit 0
  fi
  json_result "failed" "$LOG_PATH" "QNN probe completed but smoke result was inconclusive; inspect artifact."
  exit 1
}

mkdir -p "$LOG_DIR"
resolve_adb
if [ -z "$ADB_BIN" ]; then
  json_result "failed" "" "Install host adb before running the QNN device probe."
  exit 1
fi
select_device

{
  printf 'qnn_device_probe timestamp=%s app_id=%s model=%s\n' "$TIMESTAMP" "$APP_ID" "$MODEL"
  printf 'root_dir=%s\n' "$ROOT_DIR"
  printf 'apk_path=%s\n' "$APK_PATH"
  printf 'adb_bin=%s\n' "$ADB_BIN"
  printf 'android_serial=%s\n' "${ANDROID_SERIAL:-auto}"
} >"$LOG_PATH"

append_section "host apk summary"
if [ -f "$APK_PATH" ]; then
  run_host ls -lh "$APK_PATH" || true
  if command -v unzip >/dev/null 2>&1; then
    printf '$ unzip -l %s | grep -Ei "lib/|qnn|skel|stub|\\.tflite"\n' "$APK_PATH" >>"$LOG_PATH"
    unzip -l "$APK_PATH" | grep -Ei 'lib/|qnn|skel|stub|\.tflite' >>"$LOG_PATH" 2>&1
    printf '[exit=%s]\n' "$?" >>"$LOG_PATH"
  else
    printf 'unzip unavailable on host\n' >>"$LOG_PATH"
  fi
else
  printf 'debug APK missing; smoke gate will build/install if configured\n' >>"$LOG_PATH"
fi

append_section "device identity"
run_adb_shell getprop ro.product.manufacturer || true
run_adb_shell getprop ro.product.model || true
run_adb_shell getprop ro.product.device || true
run_adb_shell getprop ro.board.platform || true
run_adb_shell getprop ro.soc.model || true
run_adb_shell getprop ro.product.cpu.abilist || true
run_adb_shell getprop ro.build.version.sdk || true
run_adb_shell getprop ro.build.fingerprint || true

append_section "debug and developer settings"
run_adb_sh 'printf "development_settings_enabled="; settings get global development_settings_enabled; printf "adb_enabled="; settings get global adb_enabled; printf "enable_gpu_debug_layers="; settings get global enable_gpu_debug_layers; printf "gpu_debug_app="; settings get global gpu_debug_app; printf "wait_for_debugger="; settings get global wait_for_debugger; printf "ro_debuggable="; getprop ro.debuggable; printf "ro_secure="; getprop ro.secure; printf "ro_adb_secure="; getprop ro.adb.secure' || true

append_section "package path and native layout"
run_adb_shell "pm path $APP_ID" || true
run_adb_script "dumpsys package $APP_ID | grep -E 'Package \\[|codePath=|resourcePath=|legacyNativeLibraryDir=|primaryCpuAbi=|secondaryCpuAbi=|versionCode=|targetSdk=|flags=|privateFlags=|android.permission.CAMERA' | head -120" || true
run_adb_script "DIR=\$(dumpsys package $APP_ID | sed -n 's/.*legacyNativeLibraryDir=//p' | head -1)
echo native_dir=\$DIR
ls -la \$DIR 2>/dev/null || true
ls -la \$DIR/arm64 2>/dev/null || true
find \$DIR -maxdepth 3 \\( -iname '*qnn*' -o -iname '*skel*' -o -iname '*stub*' \\) 2>/dev/null | sort | head -160" || true
run_adb_script "run-as $APP_ID sh -c 'echo pwd=\$(pwd); echo files_dir=\$(ls -ld .); echo app_native_lib_dir_from_package; dumpsys package $APP_ID | sed -n \"s/.*legacyNativeLibraryDir=//p\" | head -1' " || true

append_section "device qnn and dsp library hints"
run_adb_script "getprop | grep -Ei 'qnn|hexagon|dsp|adsp|cdsp|vendor.*debug|soc|abi' | head -200" || true
run_adb_script "find /vendor /system /system_ext /odm -maxdepth 4 \\( -iname '*qnn*' -o -iname '*hexagon*' -o -iname '*dsp*' -o -iname '*skel*' -o -iname '*cdsp*' -o -iname '*adsp*' \\) 2>/dev/null | sort | head -220" || true

append_section "pre-smoke linker and denial hints"
"$ADB_BIN" "${DEVICE_ARG[@]}" logcat -c >/dev/null 2>&1 || true

for QNN_VARIANT in $QNN_VARIANTS; do
  append_section "qnn smoke variant=$QNN_VARIANT"
  SMOKE_OUTPUT="$(
    APP_ID="$APP_ID" \
      APK_PATH="$APK_PATH" \
      LOG_DIR="$LOG_DIR" \
      LOG_SECONDS="$LOG_SECONDS" \
      MODEL="$MODEL" \
      QNN_VARIANT="$QNN_VARIANT" \
      CAPTURE_FULL_LOGCAT=1 \
      INSTALL_FIRST=0 \
      REQUIRE_QNN_SUCCESS=1 \
      ADB_BIN="$ADB_BIN" \
      ANDROID_SERIAL="${ANDROID_SERIAL:-}" \
      "$ROOT_DIR/scripts/verify-qnn-smoke-device.sh" 2>&1
  )"
  SMOKE_STATUS=$?
  printf '%s\n' "$SMOKE_OUTPUT" >>"$LOG_PATH"
  printf '[exit=%s]\n' "$SMOKE_STATUS" >>"$LOG_PATH"
  SMOKE_ARTIFACT="$(printf '%s\n' "$SMOKE_OUTPUT" | sed -n 's/.*"artifact": "\([^"]*\)".*/\1/p' | tail -1)"

  if [ -n "$SMOKE_ARTIFACT" ] && [ -f "$SMOKE_ARTIFACT" ]; then
    append_section "smoke artifact path variant=$QNN_VARIANT"
    printf '%s\n' "$SMOKE_ARTIFACT" >>"$LOG_PATH"

    append_section "smoke qnn excerpts variant=$QNN_VARIANT"
    grep -Ei 'qnn_|Qnn|skel|transport|loadRemoteSymbols|linker|dlopen|denied|avc:' "$SMOKE_ARTIFACT" | tail -240 >>"$LOG_PATH" 2>&1 || true
  fi

  if [ "$SMOKE_STATUS" -eq 0 ]; then
    break
  fi
done

append_section "post-smoke package path and native layout"
run_adb_shell "pm path $APP_ID" || true
run_adb_script "DIR=\$(dumpsys package $APP_ID | sed -n 's/.*legacyNativeLibraryDir=//p' | head -1)
echo native_dir=\$DIR
ls -la \$DIR 2>/dev/null || true
ls -la \$DIR/arm64 2>/dev/null || true
find \$DIR -maxdepth 3 \\( -iname '*qnn*' -o -iname '*skel*' -o -iname '*stub*' \\) 2>/dev/null | sort | head -160" || true

append_section "post-smoke linker and denial hints"
"$ADB_BIN" "${DEVICE_ARG[@]}" logcat -d -v time | grep -Ei 'qnn|skel|transport|loadRemoteSymbols|linker|dlopen|denied|avc:' | tail -240 >>"$LOG_PATH" 2>&1 || true

classify_artifact
