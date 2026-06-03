#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB_BIN="${ADB_BIN:-}"
APK_PATH="${APK_PATH:-$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk}"
APP_ID="com.roana.app"
ACTIVITY="$APP_ID/.MainActivity"
DEMO_EXTRA="com.roana.app.extra.DEBUG_PRESENTATION_DEMO"

if [ -z "$ADB_BIN" ]; then
  if command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
  elif [ -x "$HOME/.local/android-platform-tools/platform-tools/adb" ]; then
    ADB_BIN="$HOME/.local/android-platform-tools/platform-tools/adb"
  fi
fi

if [ -z "$ADB_BIN" ]; then
  printf 'error: adb is not installed on the host.\n' >&2
  exit 1
fi

if [ ! -f "$APK_PATH" ]; then
  printf 'error: debug APK not found at %s\n' "$APK_PATH" >&2
  printf 'Run scripts/build-debug.sh first.\n' >&2
  exit 1
fi

device_arg=()
if [ -n "${ANDROID_SERIAL:-}" ]; then
  device_arg=(-s "$ANDROID_SERIAL")
else
  mapfile -t devices < <("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" {print $1}')
  case "${#devices[@]}" in
    0)
      printf 'error: no connected ADB device found.\n' >&2
      exit 1
      ;;
    1)
      device_arg=(-s "${devices[0]}")
      ;;
    *)
      printf 'error: multiple ADB devices found. Set ANDROID_SERIAL to choose one:\n' >&2
      printf '  %s\n' "${devices[@]}" >&2
      exit 1
      ;;
  esac
fi

"$ADB_BIN" "${device_arg[@]}" install -r "$APK_PATH" >/dev/null
"$ADB_BIN" "${device_arg[@]}" shell pm grant "$APP_ID" android.permission.CAMERA >/dev/null 2>&1 || true
"$ADB_BIN" "${device_arg[@]}" shell am force-stop "$APP_ID"
"$ADB_BIN" "${device_arg[@]}" shell am start -n "$ACTIVITY" --ez "$DEMO_EXTRA" true >/dev/null

if "$ADB_BIN" "${device_arg[@]}" shell dumpsys window policy | grep -q 'showing=true'; then
  printf 'warning: keyguard is showing. Unlock the phone to view or capture the UI.\n' >&2
fi

cat <<EOF
Roana presentation demo launched.

This mode uses synthetic depth/path data and a synthetic person box.
Long-press the bottom-right app corner for 2 seconds to toggle the debug HUD.
In debug HUD, use CAM / DEPTH / PATH / BOX / TEL to inspect layers.
EOF
