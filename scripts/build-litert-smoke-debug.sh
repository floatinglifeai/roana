#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_IMAGE="${ANDROID_BUILD_IMAGE:-cimg/android:2026.03-ndk}"
ANDROID_BUILD_PLATFORM="${ANDROID_BUILD_PLATFORM:-linux/amd64}"
GRADLE_CACHE_VOLUME="${GRADLE_CACHE_VOLUME:-roana-gradle-cache}"
ANDROID_HOME_VOLUME="${ANDROID_HOME_VOLUME:-roana-android-home}"

cd "$ROOT_DIR"

if [ ! -x "./gradlew" ]; then
  printf 'error: ./gradlew is missing or is not executable. Generate the Gradle wrapper first.\n' >&2
  exit 1
fi

if [ "${PREPARE_LITERT_QUALCOMM_RUNTIME:-0}" = "1" ]; then
  "$ROOT_DIR/scripts/prepare-litert-qualcomm-v73-runtime.sh"
fi

if [ "${PREPARE_LITERT_MAIN_NATIVE:-0}" = "1" ]; then
  main_native_source="${LITERT_MAIN_NATIVE_DIR:-$ROOT_DIR/build/litert-main-2efe1c1-qairt246/device}"
  main_native_dest="$ROOT_DIR/build/litert-main-native-jni/arm64-v8a"
  if [ ! -d "$main_native_source" ]; then
    printf 'error: LiteRT main native directory is missing: %s\n' "$main_native_source" >&2
    exit 1
  fi
  mkdir -p "$main_native_dest"
  for lib in \
    libLiteRt.so \
    libLiteRtCompilerPlugin_Qualcomm.so \
    libLiteRtDispatch_Qualcomm.so \
    libQnnHtp.so \
    libQnnHtpPrepare.so \
    libQnnHtpV73Skel.so \
    libQnnHtpV73Stub.so \
    libQnnSystem.so; do
    if [ ! -f "$main_native_source/$lib" ]; then
      printf 'error: LiteRT main native library is missing: %s/%s\n' "$main_native_source" "$lib" >&2
      exit 1
    fi
    cp -f "$main_native_source/$lib" "$main_native_dest/$lib"
  done
  if [ "${LITERT_INCLUDE_VENDOR_DSPRPC:-0}" = "1" ]; then
    adb_bin="${ADB_BIN:-}"
    if [ -z "$adb_bin" ]; then
      if command -v adb >/dev/null 2>&1; then
        adb_bin="$(command -v adb)"
      elif [ -x "$HOME/.local/android-platform-tools/platform-tools/adb" ]; then
        adb_bin="$HOME/.local/android-platform-tools/platform-tools/adb"
      fi
    fi
    if [ -z "$adb_bin" ]; then
      printf 'error: LITERT_INCLUDE_VENDOR_DSPRPC=1 requires adb in PATH or ADB_BIN.\n' >&2
      exit 1
    fi
    "$adb_bin" pull /vendor/lib64/libcdsprpc.so "$main_native_dest/libcdsprpc.so"
    "$adb_bin" pull /vendor/lib64/libadsprpc.so "$main_native_dest/libadsprpc.so"
  fi
  if [ ! -f "$main_native_source/run_model" ]; then
    printf 'error: LiteRT main run_model executable is missing: %s/run_model\n' "$main_native_source" >&2
    exit 1
  fi
  cp -f "$main_native_source/run_model" "$main_native_dest/libroana_litert_main_run_model.so"
  LITERT_EXTRA_JNI_DIR="${LITERT_EXTRA_JNI_DIR:-$ROOT_DIR/build/litert-main-native-jni}"
  LITERT_USE_ONLY_EXTRA_JNI="${LITERT_USE_ONLY_EXTRA_JNI:-1}"
fi

gradle_args=(-Dorg.gradle.vfs.watch=false)
litert_version="${LITERT_VERSION:-}"
docker_extra_args=()
if [ -z "$litert_version" ] && [ "${PREPARE_LITERT_QUALCOMM_RUNTIME:-0}" = "1" ]; then
  litert_release_tag="${LITERT_RELEASE_TAG:-v2.1.1}"
  litert_version="${litert_release_tag#v}"
fi
if [ -n "$litert_version" ]; then
  gradle_args+=("-PlitertVersion=$litert_version")
fi
if [ -n "${LITERT_LOCAL_AAR:-}" ]; then
  if [ ! -f "$LITERT_LOCAL_AAR" ]; then
    printf 'error: LITERT_LOCAL_AAR is not a file: %s\n' "$LITERT_LOCAL_AAR" >&2
    exit 1
  fi
  docker_extra_args+=(--volume "$LITERT_LOCAL_AAR:/litert-local.aar:ro")
  gradle_args+=("-PlitertLocalAar=/litert-local.aar")
fi
if [ -n "${LITERT_EXTRA_ASSET_DIR:-}" ]; then
  if [ ! -d "$LITERT_EXTRA_ASSET_DIR" ]; then
    printf 'error: LITERT_EXTRA_ASSET_DIR is not a directory: %s\n' "$LITERT_EXTRA_ASSET_DIR" >&2
    exit 1
  fi
  docker_extra_args+=(--volume "$LITERT_EXTRA_ASSET_DIR:/litert-extra-assets:ro")
  gradle_args+=("-PlitertExtraAssetDir=/litert-extra-assets")
fi
if [ -n "${LITERT_EXTRA_JNI_DIR:-}" ]; then
  if [ ! -d "$LITERT_EXTRA_JNI_DIR" ]; then
    printf 'error: LITERT_EXTRA_JNI_DIR is not a directory: %s\n' "$LITERT_EXTRA_JNI_DIR" >&2
    exit 1
  fi
  docker_extra_args+=(--volume "$LITERT_EXTRA_JNI_DIR:/litert-extra-jni:ro")
  gradle_args+=("-PlitertExtraJniDir=/litert-extra-jni")
  if [ "${LITERT_USE_ONLY_EXTRA_JNI:-0}" = "1" ]; then
    gradle_args+=("-PlitertUseOnlyExtraJni=true")
  fi
fi

mkdir -p litert-smoke/build build
chmod -R g+rwX litert-smoke/build build

docker run --rm \
  --platform "$ANDROID_BUILD_PLATFORM" \
  --user root \
  --volume "$ROOT_DIR:/workspace" \
  ${docker_extra_args+"${docker_extra_args[@]}"} \
  --volume "$GRADLE_CACHE_VOLUME:/root/.gradle" \
  --volume "$ANDROID_HOME_VOLUME:/root/.android" \
  --workdir /workspace \
  --env ANDROID_HOME=/home/circleci/android-sdk \
  --env ANDROID_SDK_ROOT=/home/circleci/android-sdk \
  --env GRADLE_USER_HOME=/root/.gradle \
  --env HOST_UID="$(id -u)" \
  --env HOST_GID="$(id -g)" \
  "$ANDROID_IMAGE" \
  bash -lc 'trap "chown -R $HOST_UID:$HOST_GID /workspace/.gradle /workspace/litert-smoke/build /workspace/build 2>/dev/null || true" EXIT; ./gradlew --no-daemon "$@" :litert-smoke:assembleDebug' \
  bash "${gradle_args[@]}"

printf '\nLiteRT smoke APK: %s\n' "$ROOT_DIR/litert-smoke/build/outputs/apk/debug/litert-smoke-debug.apk"
