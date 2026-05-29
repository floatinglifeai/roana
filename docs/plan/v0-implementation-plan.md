# V0 Implementation Plan

> Accepted implementation boundary for the first Roana code slice. This document
> resolves the earlier ambiguity between "minimum closed loop" and "full V0
> corridor demo."

**Status:** accepted for implementation / 2026-05-29.

---

## 1. Decisions

### 1.1 Official V0 app route

V0 implementation starts as a **native Kotlin Android app** using CameraX,
LiteRT/TFLite, and the Qualcomm QNN delegate path where available.

The web, PWA, and Capacitor routes remain useful research and emergency
fallbacks, but they are not the V0 implementation path.

### 1.2 V0 is split into V0a and V0b

The V0 label previously mixed two different goals. Implementation will use two
sub-slices:

| Slice | Goal | Acceptance gate |
|---|---|---|
| **V0a: minimum closed loop** | CameraX frame capture -> YOLO CPU/XNNPACK inference -> simple TTS alert | Runs on one real Android device; frame analysis does not backlog; a detected obstacle can trigger spoken output |
| **V0b: corridor demo** | Add Depth Anything, QNN/NPU path, DFS corridor decision, and conservative state machine | Known indoor corridor blindfold test with sighted spotter; pipeline reaches >=10 FPS; no 30-minute thermal throttle |

### 1.3 No custom walkable-area training in V0

V0 does **not** include custom data collection, labeling, or training for
sidewalk, stair, puddle, glass, or tactile-paving segmentation.

V0 uses off-the-shelf model assets plus conservative geometric heuristics. Custom
walkable-area training is post-V0 work.

### 1.4 V0 acceptance scenario

The V0 demo is limited to:

- a known indoor corridor;
- a blindfolded tester, not an unsupervised blind user;
- a sighted safety spotter beside the tester;
- Android phone in a chest harness;
- phone speaker TTS only.

V0 does **not** include outdoor street navigation, crosswalk guidance, BLE,
Bangle.js haptics, bone-conduction audio, smart glasses, or VLM queries.

### 1.5 Safety and privacy gates

V0 must preserve these boundaries:

- no video-frame upload;
- no frame storage by default;
- no face recognition or identity tracking;
- no cloud VLM call;
- no command that tells the user to cross a street;
- low confidence, missing frames, or uncertain geometry must prefer `STOP` over
  `CLEAR`.

These are acceptance gates, not polish tasks.

---

## 2. Implementation Order

### 2.0 Local development environment bootstrap

V0 implementation assumes this repository is built on the current Linux x86_64
machine.

Host requirements:

- Linux x86_64.
- Docker installed and usable by the current user.
- Network access for the first `cimg/android:2026.03-ndk` image pull.
- 20 GB free disk space for the Android build image, Gradle cache, and APK
  outputs.
- `adb` installed on the host for APK install and logcat capture.

Current machine status as of 2026-05-29:

- Docker is already installed: `Docker 29.1.3`, `linux/x86_64`.
- Current user is in the `docker` group.
- Host Java is Java 11, but this is not a blocker because Android builds run
  inside the Docker image with JDK 17.
- Host `adb` is installed: Android Debug Bridge 1.0.41
  (`android-tools-adb`, Debian platform-tools 28.0.2).
- No Android device is currently connected over ADB.

Bootstrap behavior:

1. Do not require Android Studio.
2. Use Docker image `cimg/android:2026.03-ndk` for Gradle builds.
3. Keep Android platform-tools / `adb` on the host, not inside the container,
   because the real phone is connected to the host.
4. Add small repo scripts before V0a implementation:
   - `scripts/check-android-env.sh` verifies Docker, disk space, and `adb`.
   - `scripts/build-debug.sh` runs `./gradlew assembleDebug` inside the Android
     Docker image.
   - `scripts/install-debug.sh` installs the debug APK to a connected device
     with `adb install -r`.

If host `adb` is missing on a future machine, install it with:

```bash
sudo apt-get update
sudo apt-get install -y android-tools-adb
```

The first Docker build will pull `cimg/android:2026.03-ndk`; this is expected to
be several GB.

### 2.1 V0a: minimum closed loop

Build the smallest real-device Android loop first:

1. Scaffold a native Kotlin Android project with Gradle wrapper.
2. Add CameraX preview and `ImageAnalysis` with
   `STRATEGY_KEEP_ONLY_LATEST`.
3. Load an off-the-shelf YOLO TFLite model from app assets.
4. Run initial inference with CPU/XNNPACK.
5. Convert one simple detection event into Android `TextToSpeech` output.
6. Log frame timing, inference timing, dropped-frame count, and TTS events.

V0a deliberately skips depth, path planning, BLE, foreground lock-screen
operation, and distribution concerns.

### 2.2 V0b: corridor demo

After V0a is stable:

1. Add Depth Anything V2-Small mobile asset.
2. Add QNN delegate initialization with safe fallback.
3. Combine depth output and obstacle detections into a coarse 15x15 grid.
4. Implement DFS corridor extraction and a conservative state machine.
5. Add emergency override for near obstacle, frame loss, and low confidence.
6. Run the known-corridor blindfold test with a sighted spotter.

V0b succeeds only if the end-to-end pipeline reaches the documented safety and
performance gates.

---

## 3. Out of Scope for V0

- BLE and Bangle.js 2.
- Bone-conduction headset routing.
- Smart-glasses camera source.
- Cloud or on-device VLM query flow.
- Custom model training.
- App-store distribution.
- Outdoor street navigation.
- Crosswalk or traffic-light command output.
- Unsupervised testing with blind users.

---

## 4. Next Execution Step

Create the native Android skeleton and build/test harness:

- `scripts/check-android-env.sh`, `scripts/build-debug.sh`,
  `scripts/install-debug.sh`;
- `settings.gradle.kts`, root `build.gradle.kts`, Gradle wrapper;
- `app/` module with Compose or a minimal native Activity;
- Android manifest with camera permission;
- CameraX preview plus analysis callback;
- first timing logs before adding model inference.

The first implementation commit should prove that the Android project builds and
runs on a real device before model assets are added.

---

## 5. Test and Handoff Plan

V0a will be tested from a debug APK.

Developer-side loop:

1. Build: `scripts/build-debug.sh`.
2. Produce: `app/build/outputs/apk/debug/app-debug.apk`.
3. If a phone is connected over USB or wireless ADB, install with
   `scripts/install-debug.sh`.
4. Capture logs with `adb logcat`, filtered by Roana app tags.

User-side V0a test:

1. Use a real Android phone with USB debugging enabled.
2. Install the debug APK through ADB, or manually install the APK if ADB is not
   connected.
3. Open the app and grant camera permission.
4. Confirm CameraX preview starts.
5. Point the camera at a simple object/person scenario.
6. Confirm the app emits a simple TTS event.
7. Run for 5 minutes and report crashes, permission failures, camera freeze,
   overheating, or repeated/late speech.

V0b test:

1. Use the same APK flow.
2. Use a known indoor corridor only.
3. Use a blindfolded tester only with a sighted spotter beside them.
4. Record whether the app reaches >=10 FPS, avoids frame backlog, and prefers
   STOP on uncertainty.
5. Run a 30-minute thermal/throttling check before considering the V0b demo
   passed.

Device requirements:

| Slice | Minimum practical phone | Why |
|---|---|---|
| **V0a** | Android 12+ arm64 phone with rear camera and working TTS | CPU/XNNPACK YOLO smoke test, no depth or NPU required |
| **V0b** | Snapdragon 8 Gen 2 / Gen 3 / Elite, or Dimensity 9300/9400-class Android phone; 8-12 GB RAM recommended | Depth Anything V2-Small needs NPU-class performance to reach the >=10 FPS gate |

No Google Play account, app-store signing, MIIT filing, or release keystore is
needed for V0a/V0b self-test. Debug APK plus ADB install is enough.
