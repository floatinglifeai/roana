#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${DEST_DIR:-$ROOT_DIR/litert-smoke/src/main/jniLibs/arm64-v8a}"
SOURCE_DIR="${LITERT_QUALCOMM_RUNTIME_DIR:-}"
FALLBACK_QNN_LIB_DIR="${APP_QNN_LIB_DIR:-$ROOT_DIR/app/build/intermediates/merged_native_libs/debug/mergeDebugNativeLibs/out/lib/arm64-v8a}"
LITERT_RELEASE_TAG="${LITERT_RELEASE_TAG:-v2.1.1}"
LITERT_RUNTIME_ZIP="${LITERT_QUALCOMM_RUNTIME_ZIP:-}"
LITERT_RUNTIME_WORK_DIR="${LITERT_QUALCOMM_RUNTIME_WORK_DIR:-$ROOT_DIR/.gradle/litert-qualcomm-runtime/$LITERT_RELEASE_TAG}"
QAIRT_URL="${QAIRT_URL:-https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/2.41.0.251128/v2.41.0.251128.zip}"
QAIRT_CONTENT_DIR="${QAIRT_CONTENT_DIR:-qairt/2.41.0.251128}"
QAIRT_ZIP="${QAIRT_ZIP:-$LITERT_RUNTIME_WORK_DIR/qairt_sdk.zip}"

runtime_libs=(
  libLiteRtCompilerPlugin_Qualcomm.so:679176
  libLiteRtDispatch_Qualcomm.so:476880
  libQnnHtp.so:2595312
  libQnnHtpPrepare.so:78131288
  libQnnHtpV73Skel.so:10228984
  libQnnHtpV73Stub.so:582040
  libQnnSystem.so:2646184
)

download_file() {
  local url="$1"
  local out="$2"

  if command -v curl >/dev/null 2>&1; then
    curl \
      --connect-timeout 20 \
      --max-time 420 \
      --retry 3 \
      --retry-all-errors \
      --retry-delay 2 \
      -L --fail --show-error --silent \
      "$url" \
      -o "$out"
    return
  fi

  printf 'error: curl or gh is required to fetch LiteRT Qualcomm runtime libraries.\n' >&2
  exit 1
}

download_litert_jit_zip() {
  local out="$1"

  if [ -n "$LITERT_RUNTIME_ZIP" ]; then
    if [ ! -f "$LITERT_RUNTIME_ZIP" ]; then
      printf 'error: LITERT_QUALCOMM_RUNTIME_ZIP is missing: %s\n' "$LITERT_RUNTIME_ZIP" >&2
      exit 1
    fi
    cp "$LITERT_RUNTIME_ZIP" "$out"
    return
  fi

  if command -v gh >/dev/null 2>&1; then
    gh release download "$LITERT_RELEASE_TAG" \
      --repo google-ai-edge/LiteRT \
      --pattern litert_npu_runtime_libraries_jit.zip \
      --dir "$(dirname "$out")" \
      --clobber
    return
  fi

  download_file \
    "https://github.com/google-ai-edge/LiteRT/releases/download/$LITERT_RELEASE_TAG/litert_npu_runtime_libraries_jit.zip" \
    "$out"
}

prepare_source_dir() {
  local runtime_dir="$LITERT_RUNTIME_WORK_DIR/qualcomm_runtime_v73/src/main/jni/arm64-v8a"

  if [ -n "$SOURCE_DIR" ]; then
    printf '%s\n' "$SOURCE_DIR"
    return
  fi

  mkdir -p "$LITERT_RUNTIME_WORK_DIR"

  if [ ! -f "$runtime_dir/libLiteRtCompilerPlugin_Qualcomm.so" ] ||
    [ ! -f "$runtime_dir/libLiteRtDispatch_Qualcomm.so" ]; then
    rm -rf "$LITERT_RUNTIME_WORK_DIR/extracted"
    mkdir -p "$LITERT_RUNTIME_WORK_DIR/extracted"
    download_litert_jit_zip "$LITERT_RUNTIME_WORK_DIR/litert_npu_runtime_libraries_jit.zip"
    unzip -q -o "$LITERT_RUNTIME_WORK_DIR/litert_npu_runtime_libraries_jit.zip" \
      -d "$LITERT_RUNTIME_WORK_DIR/extracted"
    cp -R "$LITERT_RUNTIME_WORK_DIR/extracted/qualcomm_runtime_v73" \
      "$LITERT_RUNTIME_WORK_DIR/qualcomm_runtime_v73"
  fi

  if [ ! -f "$runtime_dir/libQnnHtpPrepare.so" ]; then
    mkdir -p "$(dirname "$QAIRT_ZIP")"
    if [ ! -f "$QAIRT_ZIP" ]; then
      download_file "$QAIRT_URL" "$QAIRT_ZIP"
    fi
    rm -rf "$LITERT_RUNTIME_WORK_DIR/qairt"
    unzip -q -o "$QAIRT_ZIP" '*.so' -d "$LITERT_RUNTIME_WORK_DIR"

    local qairt_dir="$LITERT_RUNTIME_WORK_DIR/$QAIRT_CONTENT_DIR"
    cp "$qairt_dir/lib/aarch64-android/libQnnHtp.so" "$runtime_dir/"
    cp "$qairt_dir/lib/aarch64-android/libQnnHtpPrepare.so" "$runtime_dir/"
    cp "$qairt_dir/lib/aarch64-android/libQnnHtpV73Stub.so" "$runtime_dir/"
    cp "$qairt_dir/lib/aarch64-android/libQnnSystem.so" "$runtime_dir/"
    cp "$qairt_dir/lib/hexagon-v73/unsigned/libQnnHtpV73Skel.so" "$runtime_dir/"
  fi

  printf '%s\n' "$runtime_dir"
}

copy_lib() {
  local lib="$1"
  local expected_size="$2"
  local source_dir="$3"
  local dest="$DEST_DIR/$lib"
  local tmp="$dest.tmp"
  local existing_size

  if [ -f "$dest" ]; then
    existing_size="$(wc -c <"$dest" | tr -d ' ')"
    if [ "$existing_size" = "$expected_size" ]; then
      return
    fi
  fi

  if [ ! -f "$source_dir/$lib" ]; then
    printf 'error: source runtime directory is missing %s: %s\n' "$lib" "$source_dir" >&2
    exit 1
  fi
  cp "$source_dir/$lib" "$tmp"

  local actual_size
  actual_size="$(wc -c <"$tmp" | tr -d ' ')"
  if [ "$actual_size" != "$expected_size" ]; then
    printf 'error: %s has unexpected size: got %s bytes, expected %s bytes.\n' "$lib" "$actual_size" "$expected_size" >&2
    printf 'hint: set LITERT_QUALCOMM_RUNTIME_DIR to a matched LiteRT release JIT qualcomm_runtime_v73 arm64-v8a directory, or set LITERT_RELEASE_TAG/QAIRT_URL to matching releases.\n' >&2
    rm -f "$tmp"
    exit 1
  fi

  mv "$tmp" "$dest"
}

copy_fallback_qnn_libs() {
  local lib

  if [ ! -d "$FALLBACK_QNN_LIB_DIR" ]; then
    printf 'error: fallback QNN native library directory is missing: %s\n' "$FALLBACK_QNN_LIB_DIR" >&2
    printf 'hint: run scripts/build-debug.sh first, set LITERT_QUALCOMM_RUNTIME_DIR, or leave LITERT_QUALCOMM_RUNTIME_ALLOW_FALLBACK unset to fail on mismatched runtime packaging.\n' >&2
    exit 1
  fi

  for entry in "${runtime_libs[@]}"; do
    lib="${entry%%:*}"
    if [ "$lib" = "libLiteRtDispatch_Qualcomm.so" ]; then
      printf 'error: fallback mode cannot provide a matched LiteRT dispatch/compiler plugin set.\n' >&2
      printf 'hint: unset LITERT_QUALCOMM_RUNTIME_ALLOW_FALLBACK or set LITERT_QUALCOMM_RUNTIME_DIR.\n' >&2
      exit 1
      continue
    fi
    if [ ! -f "$FALLBACK_QNN_LIB_DIR/$lib" ]; then
      printf 'error: fallback QNN native library is missing: %s/%s\n' "$FALLBACK_QNN_LIB_DIR" "$lib" >&2
      exit 1
    fi
    cp "$FALLBACK_QNN_LIB_DIR/$lib" "$DEST_DIR/$lib"
  done

  printf 'warning: using fallback QNN libraries from %s; these may not match the LiteRT Qualcomm dispatch runtime.\n' "$FALLBACK_QNN_LIB_DIR" >&2
}

mkdir -p "$DEST_DIR"

if [ "${LITERT_QUALCOMM_RUNTIME_ALLOW_FALLBACK:-0}" = "1" ] && [ -z "$SOURCE_DIR" ]; then
  copy_fallback_qnn_libs
else
  SOURCE_DIR="$(prepare_source_dir)"
  for entry in "${runtime_libs[@]}"; do
    copy_lib "${entry%%:*}" "${entry#*:}" "$SOURCE_DIR"
  done
fi

printf 'Prepared LiteRT Qualcomm v73 runtime libraries in %s\n' "$DEST_DIR"
ls -lh \
  "$DEST_DIR"/libLiteRtCompilerPlugin_Qualcomm.so \
  "$DEST_DIR"/libLiteRtDispatch_Qualcomm.so \
  "$DEST_DIR"/libQnnHtp.so \
  "$DEST_DIR"/libQnnHtpPrepare.so \
  "$DEST_DIR"/libQnnHtpV73Skel.so \
  "$DEST_DIR"/libQnnHtpV73Stub.so \
  "$DEST_DIR"/libQnnSystem.so
