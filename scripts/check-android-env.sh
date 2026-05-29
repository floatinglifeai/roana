#!/usr/bin/env bash
set -euo pipefail

REQUIRED_DISK_GB="${REQUIRED_DISK_GB:-20}"
ANDROID_IMAGE="${ANDROID_BUILD_IMAGE:-cimg/android:2026.03-ndk}"
ANDROID_BUILD_PLATFORM="${ANDROID_BUILD_PLATFORM:-linux/amd64}"
ADB_BIN="${ADB_BIN:-}"

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

host_os="$(uname -s)"
host_arch="$(uname -m)"

case "$host_os/$host_arch" in
  Linux/x86_64)
    printf 'ok: host is Linux x86_64\n'
    ;;
  Darwin/arm64)
    printf 'ok: host is macOS arm64; Docker build will use %s\n' "$ANDROID_BUILD_PLATFORM"
    printf 'warn: enable Docker Desktop Rosetta for faster amd64 Android builds\n' >&2
    ;;
  *)
    printf 'error: unsupported host %s/%s; expected Linux/x86_64 or macOS/arm64\n' "$host_os" "$host_arch" >&2
    failures=$((failures + 1))
    ;;
esac

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

if [ -z "$ADB_BIN" ]; then
  if command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
  elif [ -x "$HOME/.local/android-platform-tools/platform-tools/adb" ]; then
    ADB_BIN="$HOME/.local/android-platform-tools/platform-tools/adb"
  fi
fi

if [ -n "$ADB_BIN" ]; then
  printf 'ok: adb is available at %s\n' "$ADB_BIN"
else
  printf 'error: adb is not available\n' >&2
  failures=$((failures + 1))
fi

check_warn "at least one ADB device is connected" bash -lc "'$ADB_BIN' devices | awk 'NR > 1 && \$2 == \"device\" {found = 1} END {exit found ? 0 : 1}'"
check_warn "Android build image already present locally ($ANDROID_IMAGE)" docker image inspect "$ANDROID_IMAGE"

if [ "$failures" -gt 0 ]; then
  printf '\nAndroid environment check failed with %s error(s).\n' "$failures" >&2
  exit 1
fi

printf '\nAndroid environment check passed. Warnings may still require action before device install.\n'
