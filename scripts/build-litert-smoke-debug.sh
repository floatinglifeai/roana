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
