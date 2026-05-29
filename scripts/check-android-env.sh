#!/usr/bin/env bash
set -euo pipefail

REQUIRED_DISK_GB="${REQUIRED_DISK_GB:-20}"
ANDROID_IMAGE="${ANDROID_BUILD_IMAGE:-cimg/android:2026.03-ndk}"

failures=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'ok: %s\n' "$label"
  else
    printf 'error: %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

check_warn() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'ok: %s\n' "$label"
  else
    printf 'warn: %s\n' "$label" >&2
  fi
}

check "host is Linux" test "$(uname -s)" = "Linux"
check "host architecture is x86_64" test "$(uname -m)" = "x86_64"

check "docker command exists" command -v docker
check "docker daemon is usable" docker info

available_kb=$(df -Pk . | awk 'NR == 2 {print $4}')
available_gb=$((available_kb / 1024 / 1024))
if [ "$available_gb" -ge "$REQUIRED_DISK_GB" ]; then
  printf 'ok: disk space %s GB available\n' "$available_gb"
else
  printf 'error: disk space %s GB available, need %s GB\n' "$available_gb" "$REQUIRED_DISK_GB" >&2
  failures=$((failures + 1))
fi

check "adb command exists" command -v adb
check_warn "at least one ADB device is connected" bash -lc "adb devices | awk 'NR > 1 && \$2 == \"device\" {found = 1} END {exit found ? 0 : 1}'"
check_warn "Android build image already present locally ($ANDROID_IMAGE)" docker image inspect "$ANDROID_IMAGE"

if [ "$failures" -gt 0 ]; then
  printf '\nAndroid environment check failed with %s error(s).\n' "$failures" >&2
  exit 1
fi

printf '\nAndroid environment check passed. Warnings may still require action before device install.\n'
