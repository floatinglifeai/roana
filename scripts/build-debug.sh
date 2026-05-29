#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_IMAGE="${ANDROID_BUILD_IMAGE:-cimg/android:2026.03-ndk}"
GRADLE_CACHE_VOLUME="${GRADLE_CACHE_VOLUME:-roana-gradle-cache}"
ANDROID_HOME_VOLUME="${ANDROID_HOME_VOLUME:-roana-android-home}"

cd "$ROOT_DIR"

if [ ! -x "./gradlew" ]; then
  printf 'error: ./gradlew is missing or is not executable. Generate the Gradle wrapper first.\n' >&2
  exit 1
fi

mkdir -p app/build build
chmod -R g+rwX app/build build

docker run --rm \
  --user root \
  --volume "$ROOT_DIR:/workspace" \
  --volume "$GRADLE_CACHE_VOLUME:/root/.gradle" \
  --volume "$ANDROID_HOME_VOLUME:/root/.android" \
  --workdir /workspace \
  --env ANDROID_HOME=/home/circleci/android-sdk \
  --env ANDROID_SDK_ROOT=/home/circleci/android-sdk \
  --env GRADLE_USER_HOME=/root/.gradle \
  --env HOST_UID="$(id -u)" \
  --env HOST_GID="$(id -g)" \
  "$ANDROID_IMAGE" \
  bash -lc 'trap "chown -R $HOST_UID:$HOST_GID /workspace/.gradle /workspace/app/build /workspace/build 2>/dev/null || true" EXIT; ./gradlew --no-daemon assembleDebug'

printf '\nDebug APK: %s\n' "$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk"
