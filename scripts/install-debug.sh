#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_PATH="${APK_PATH:-$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk}"

if [ ! -f "$APK_PATH" ]; then
  printf 'error: debug APK not found at %s\n' "$APK_PATH" >&2
  printf 'Run scripts/build-debug.sh first.\n' >&2
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  printf 'error: adb is not installed on the host.\n' >&2
  exit 1
fi

mapfile -t devices < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')

if [ -n "${ANDROID_SERIAL:-}" ]; then
  adb -s "$ANDROID_SERIAL" install -r "$APK_PATH"
elif [ "${#devices[@]}" -eq 1 ]; then
  adb -s "${devices[0]}" install -r "$APK_PATH"
elif [ "${#devices[@]}" -eq 0 ]; then
  printf 'error: no connected ADB device found.\n' >&2
  printf 'Connect a phone with USB debugging enabled, or set ANDROID_SERIAL for wireless ADB.\n' >&2
  exit 1
else
  printf 'error: multiple ADB devices found. Set ANDROID_SERIAL to choose one:\n' >&2
  printf '  %s\n' "${devices[@]}" >&2
  exit 1
fi
