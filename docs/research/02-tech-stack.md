# Tech Stack Selection — Mac → Android

> Which language and framework to use for building Roana, given the constraints: Apple Silicon Mac as primary dev machine, Android-first (iOS later if cheap), the founder has no mobile-dev experience and leans heavily on Claude for code generation.

---

## TL;DR

**Recommended: native Kotlin + Android Studio (Apple Silicon native build) + LiteRT/TFLite + QNN NPU Delegate.**

Three reasons:

1. **NPU is a first-class citizen only on the native route.** Project bottleneck is Depth Anything V2-Small. Qualcomm AI Hub measurements: FP16 NPU inference is **50.806 ms on Snapdragon 8 Gen 3 (Galaxy S24) / TFLITE** (~19.7 FPS); **72.541 ms on Snapdragon 8 Gen 2** (QCS8550 proxy, ~Galaxy S23, ~13.8 FPS); **35.628 ms on Snapdragon 8 Elite for Galaxy** (~28 FPS). YOLOv8n W8A8 INT8 is **0.898 ms on 8 Gen 3 NPU**; YOLO11n **1.105 ms**. **Without NPU, Depth Anything V2 on CPU is 10–20× slower, dropping to 1–2 FPS — the product doesn't work.** Google announced "LiteRT Qualcomm AI Engine Direct (QNN) Accelerator" on 2025-11-24 (Developers Blog, authors Lu Wang / Weiyi Wang / Andrew Zhang), letting Kotlin/Java apps call Qualcomm HTP NPU via two lines of Gradle dependency. Equivalent support in cross-platform frameworks lags 1–2 generations or requires writing native modules.
2. **AI-assistance friendliness actually favors Kotlin.** Claude Sonnet 4.5 (Anthropic announcement 2025-09-29, SWE-bench Verified 77.2%) and Opus 4.5 (2025-11-24, SWE-bench Verified 80.9%, "first model to exceed 80% threshold") official notes state Sonnet 4.5 "supports Kotlin, with stronger results in Python and JavaScript" — Kotlin supported but slightly weaker than Python/JS. **But:** Android is the world's largest mobile-dev corpus; Claude Code, Android Studio + AI plugins, and official Android docs are LLM-friendly. For zero-experience + heavy-AI usage, the biggest cost is debugging errors, and Android+Kotlin has the highest density of error messages and community answers.
3. **The "cost" of cross-platform iOS is severely underestimated.** Flutter / RN "one codebase, two platforms" holds only at the UI layer. Vision inference on iOS must be rewritten for Core ML + Vision. BLE / foreground Service / CameraX all need separate handling. Almost every hard part of this project (NPU, camera, Bluetooth, background persistence) lives in the layer that *doesn't* share. For zero-experience + heavy-AI, cross-platform benefit ≈ 0, complexity ≈ 2×.

**"Easiest possible start" path:**

1. Install Android Studio Apple Silicon native + JDK 17 + Android SDK/NDK.
2. Generate an Empty Compose Activity (Kotlin + Jetpack Compose) from the Android Studio template.
3. Add `androidx.camera:camera-camera2 + camera-view` (CameraX), `com.google.ai.edge.litert:litert` (LiteRT main), `com.qualcomm.qti:qnn-runtime + qnn-litert-delegate` (NPU delegate), `no.nordicsemi.android:ble` (Nordic BLE).
4. First get YOLO11n (~6 MB INT8 TFLite) "camera frame → detection box" pipeline working with LiteRT CPU/GPU delegate.
5. Then switch to QNN delegate to hit NPU; then add Depth Anything V2.
6. Throughout, let Claude Code write inside the Android Studio terminal, read logcat, and edit Gradle.

**iOS handling:** in V0–V2 phases, **don't do iOS**. After Android is stable and demand is validated, either use KMP (Kotlin Multiplatform) or write a separate iOS project. **Don't** switch to Flutter / RN to get iOS for free.

> **2026-05 founder update:** Linux as dev machine confirmed instead of Apple Silicon → all Rosetta / QEMU performance concerns vanish (Linux x86_64 is native for Android command-line tools / NDK). Docker still useful for environment reproducibility (Mac, Linux, GitHub Actions all using the same image). See [04-build-and-distribution.md](04-build-and-distribution.md) for the headless build flow.

---

## Five Tech Stack Routes — Deep Comparison

### Route 1 — Native Kotlin + Android Studio (RECOMMENDED)

- **NPU / performance:** ✅ first-class citizen. LiteRT (TFLite's 2025 rebrand) officially provides QNN Accelerator; one-line Maven dependency `com.qualcomm.qti:qnn-litert-delegate:2.34.0`. Per Google's 2025-11-24 benchmark, 90 LiteRT operators covered, 64 of 72 common ML models can fully NPU-offload, up to 100× speedup vs CPU and 10× vs GPU (source: Google Developers Blog *"Unlocking Peak Performance on Qualcomm NPU with LiteRT"*). MediaTek NeuroPilot delegate is exposed via the same LiteRT CompiledModel API. ONNX Runtime 1.24 on Maven has `com.microsoft.onnxruntime:onnxruntime-android-qnn`, QNN EP direct to Hexagon HTP — fallback option.
- **Real-device debugging:** ✅ Android Studio one-click USB/wireless ADB, logcat, profiler, Layout Inspector, Compose Preview all in one IDE.
- **AI-assistance friendliness:** ✅ Claude has official Kotlin/Android support; Android Studio embeds Gemini, and supports running Claude Code in its built-in terminal. Common pitfalls all have StackOverflow answers.
- **Cross-platform iOS cost:** ❌ not cross-platform out of the box. Later option: Kotlin Multiplatform (KMP) for shared business logic; UI still SwiftUI.
- **Learning curve:** medium-steep (Gradle, Manifest, permissions, lifecycle concepts), but Claude handles most.
- **Community maturity:** ✅✅✅ highest.
- **Especially fitting for this project:** CameraX, `androidx.camera-mlkit-vision`, Foreground Service (`type=camera|connectedDevice`), `android.bluetooth.*` GATT API, `TextToSpeech` system API are all first-class natives. Future Rokid smart-glasses integration (their SDK is Android/Kotlin) is near-zero migration cost.

### Route 2 — Flutter (Dart)

- **NPU / performance:** ⚠️ half-ecosystem. Community-mainstream `tflite_flutter` only exposes CPU / GPU / NNAPI delegates, **does not directly expose QNN**. Ultralytics's official `ultralytics_yolo` Flutter plugin (newer, YOLO-focused) similarly doesn't directly support QNN. Using NPU requires writing a platform-channel + Kotlin native module to load QNN — extremely hard for zero-experience users. NNAPI itself is deprecated in Android 15 per Android NDK official docs (*"deprecated in Android 15"*), meaning Flutter / RN's current NNAPI path is unsustainable long-term.
- **Real-device debugging:** ✅ `flutter run` works well; Flutter toolchain mostly native on Apple Silicon (some tools still go through Rosetta 2).
- **AI-assistance friendliness:** ✅ Claude writes Dart / Flutter capably; Sonnet series has good Flutter training coverage per community feedback.
- **Cross-platform iOS cost:** ⚠️ UI layer essentially free; inference layer must switch to CoreML delegate or rewrite in Core ML.
- **Learning curve:** medium.
- **Community maturity:** ✅✅ high, but CV/NPU sub-line is thin.
- **Verdict:** UI is pretty, two-platform shipping is fast, but **for NPU you'll eventually have to write Kotlin native modules anyway** — meaning you learn both Flutter and Android-native, doubling learning cost.

### Route 3 — React Native (TypeScript)

- **NPU / performance:** ⚠️ slightly better than Flutter but still not first-class. `react-native-fast-tflite` (by mrousavy/Margelo) is the most performant TFLite RN library, JSI zero-copy based, loads `android-gpu` and `nnapi` delegates but **doesn't expose QNN**. Requires writing Nitro / native modules. `react-native-vision-camera`'s Frame Processor + Worklets provide an excellent real-time frame pipeline (official docs: *"Frame Processors can run more than 1000 times a second"*) — the killer feature for the CV route.
- **Real-device debugging:** ✅ Metro + Flipper + adb.
- **AI-assistance friendliness:** ✅✅ JavaScript / TypeScript is one of Claude's strongest languages — Sonnet 4.5 official: "stronger results in Python and JavaScript."
- **Cross-platform iOS cost:** similar to Flutter; iOS side needs CoreML delegate.
- **Learning curve:** medium.
- **JS/TS ecosystem synergy:** ✅ same language as MentraOS SDK (TypeScript) — theoretically business logic can be reused, but MentraOS is a server-side framework (runs in cloud / local backend, glasses route through phone via BLE), and the phone app's vision processing is a separate process anyway. "Same language" synergy is actually limited.
- **Verdict:** if you have far more JS/TS experience than Kotlin and don't mind the 2–3× NPU performance loss, it's the runner-up. Otherwise, native.

### Route 4 — Python (Kivy / BeeWare / Chaquopy)

- **NPU / performance:** ❌ near-dead-end. Kivy/BeeWare's TFLite Python bindings go through CPU; **cannot call QNN delegate**. NNAPI delegate on the python-for-android path is essentially unmaintained. Chaquopy embeds a Python interpreter in a native Android project — lets Python code call a Kotlin-held TFLite Interpreter — but means you **first write a native Kotlin project**, then embed Python. If you've already set up the native project, adding Python is pure complexity and APK bloat.
- **Real-device debugging:** ⚠️ Kivy/Buildozer on Apple Silicon has historical issues; slow build, needs Docker/VM. BeeWare (Briefcase) newer but still early. Bleak official docs (bleak.readthedocs.io/en/latest/backends/android.html) say: "*the python-for-android backend has not been fully tested*" — BLE, a critical dependency for us, is unreliable.
- **AI-assistance friendliness:** Python is Claude's strongest language nominally, but **mobile-Python corpus is sparse** — what you actually need is "Kivy + Android permissions + BLE + foreground Service corpus," which is thin enough that AI hallucinates frequently.
- **Camera / BLE / TTS / foreground Service:** Plyer / pyjnius partial support, many pitfalls.
- **Verdict:** ❌ not suitable for this project, not even for prototyping.

### Route 5 — Hybrid / Mixed Approaches

- **Kotlin shell + Chaquopy running Python algorithms:** only makes sense if you have **lots of existing Python code to reuse**. This project's algorithm layer is almost entirely TFLite models + geometric state machine — no such code asset. Mixing in Python is pure burden.
- **Flutter / RN UI + native Kotlin inference module (platform channel / Nitro):** the **only** practical way to get NPU on Flutter / RN; multiple production teams do this. But for zero-experience users you need to grasp "Dart/JS layer + Kotlin layer + bridge protocol between them," and most difficulty concentrates in the bridge. **Cost > benefit.**
- **The only worth-considering hybrid:** native Kotlin app + remote Python server (during development) for model experiments / prototyping. Use Python purely for offline training / conversion / validation; mobile is pure Kotlin.

### Total Comparison Table

| Dimension | Native Kotlin | Flutter | React Native | Python (Kivy/BeeWare) | Hybrid (RN/Flutter + native) |
|---|---|---|---|---|---|
| **NPU support** | ✅ QNN/NeuroPilot first-class | ⚠️ self-written native module | ⚠️ self-written Nitro module | ❌ none | ✅ (but native required) |
| **Real-device debug** | ✅ Android Studio native | ✅ flutter run | ✅ Metro+adb | ⚠️ buildozer slow, many pitfalls | ✅ |
| **AI writes code** | ✅ Claude official "supports Kotlin" + massive corpus | ✅ Sonnet Dart feedback good | ✅✅ JS/TS Sonnet official "stronger" | ⚠️ Python strong ≠ mobile-Python strong | ⚠️ bridge layer corpus sparse |
| **Cross-platform iOS** | ❌ later KMP possible | ⚠️ UI free, inference rewrite | ⚠️ UI free, inference rewrite | ❌ | ⚠️ |
| **Learning curve** | medium-steep | medium | medium | seemingly-low actually-high | high |
| **Community maturity** | ✅✅✅ | ✅✅ | ✅✅ | ⚠️ | ⚠️ |
| **CameraX/BLE/FGS** | ✅ native | ✅ plugins complete | ✅ plugins complete | ⚠️ incomplete | ✅ |
| **This project recommendation** | ★★★★★ | ★★★ | ★★★ | ★ | ★★ |

---

## Apple Silicon Mac Android Development Setup

> Note: founder switched to Linux as primary dev machine in May 2026; this section preserved for any future Mac contributor.

### Required components

1. **Android Studio Apple Silicon native** (download page has a "Mac with Apple chip" option; **don't** install Intel version on Rosetta). Recent stable branches (Ladybug / Koala) are fully ARM64 native.
2. **JDK 17** (Android Gradle Plugin 8.x+ minimum requires Java 17). Android Studio's bundled JBR is 17+; command line needs separate install: `brew install --cask zulu@17` or `brew install openjdk@17`.
3. **Android SDK + Platform-Tools + Build-Tools:** Android Studio → SDK Manager → latest stable API (recommended API 34 + 35; for this project minSdk should be 31 because QNN NPU needs it).
4. **Android NDK:** SDK Manager → SDK Tools → check NDK (Side by Side) + CMake. LiteRT / ONNX Runtime native libs need NDK.
5. **arm64-v8a system images:** on Apple Silicon must use ARM64 system images (not x86_64); newer images (API 30+) natively support — no HAXM (Intel virtualization, which M-chip does not support; uses Apple Hypervisor.framework instead).
6. **No cost:** all Android development is free; only Google Play upload requires a one-time $25 developer registration.

### First-launch check

```bash
java -version          # should show 17.x
echo $ANDROID_HOME     # ~/Library/Android/sdk
adb --version          # platform-tools ready
adb devices            # phone in dev mode + USB debug should appear
```

In `~/.zshrc`:
```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin
```

### Emulator vs Real Device: this project requires real device

| Capability | Android Emulator (AVD) | Real Device |
|---|---|---|
| UI / logic debug | ✅ ARM64 image near-native on M chip | ✅ |
| Camera | ⚠️ only virtual scene / Mac webcam | ✅ |
| Bluetooth BLE | ❌ completely unsupported | ✅ |
| NPU (Hexagon/HTP) | ❌ no real NPU; auto-fallback CPU | ✅ |
| IMU sensors | ⚠️ manual inject | ✅ |

**Conclusion:** project needs a Snapdragon 8 Gen 2 / Gen 3 / Elite phone (OnePlus, Xiaomi, Galaxy S23+ / S24+ / S25 all work) to validate NPU path. MediaTek flagship (Dimensity 9300+) can also go NeuroPilot delegate route. Used Galaxy S23 (8 Gen 2) is budget-friendly — measured Depth Anything V2 FP16 at 72.5 ms / TFLite NPU (~13.8 FPS).

### Real-device debug essentials

1. Phone "Developer options" → "USB debugging" → "Wireless debugging" (Android 11+).
2. First USB connect pops "Allow this computer to debug" — must accept.
3. Wireless debug: phone and Mac on same Wi-Fi; phone "Wireless debugging" page shows IP:Port and pairing code; `adb pair IP:PORT` → `adb connect IP:PORT`.
4. **Use Android Studio's logcat panel, not terminal** — filter by tag, by level, paste / screenshot into Claude Code for diagnosis.

---

## Model Deployment and NPU Invocation

### 4.1 Model sources and formats

| Model | Recommended source | Format | Size |
|---|---|---|---|
| YOLO11n / YOLOv8n | Qualcomm AI Hub | `.tflite` (W8A8 INT8) | ~6 MB |
| Depth Anything V2-Small | Qualcomm AI Hub | `.tflite` (FP16) or `.dlc` QNN | 94.3 MB (Qualcomm AI Hub official "Model size (float)") |

**Key facts (Qualcomm AI Hub measured, aihub.qualcomm.com & corresponding HF model cards):**

| Model | Device / SoC | Runtime | Precision | Inference (ms) | Implied FPS |
|---|---|---|---|---|---|
| Depth-Anything-V2 Small | Snapdragon 8 Gen 3 (Galaxy S24) | TFLITE | FP16 | **50.806** | ~19.7 |
| Depth-Anything-V2 Small | Snapdragon 8 Gen 2 / QCS8550 proxy (S23) | TFLITE | FP16 | **72.541** | ~13.8 |
| Depth-Anything-V2 Small | Snapdragon 8 Elite for Galaxy | TFLITE | FP16 | **35.628** | ~28.1 |
| Depth-Anything-V2 Small | Snapdragon 8 Elite Gen 5 | TFLITE | FP16 | **31.521** | ~31.7 |
| YOLOv8n | Snapdragon 8 Gen 3 | TFLITE | W8A8 INT8 | **0.898** | ~1114 |
| YOLOv8n | Snapdragon 8 Gen 2 (QCS8550 proxy) | TFLITE | W8A8 INT8 | **1.318** | ~759 |
| YOLO11n | Snapdragon 8 Gen 3 | TFLITE | W8A8 INT8 | **1.105** | ~905 |
| YOLO11n | Snapdragon 8 Gen 2 (QCS8550 proxy) | TFLITE | W8A8 INT8 | **1.636** | ~611 |

**Important constraint:** Qualcomm AI Hub has **not released** an INT8 mobile version of Depth Anything V2 — only FP16 for Snapdragon 8 Gen 2/3/Elite (Snapdragon X laptop chips have a W8A16 ONNX variant only). This is a hard project constraint. Overall: **Depth Anything V2 is the only bottleneck;** YOLO is essentially free. 10–15 FPS full pipeline on 8 Gen 2+ phones is fully feasible, **provided NPU is used.** CPU would be 10–20× slower, dropping to unusable territory.

### 4.2 Gradle dependencies (Kotlin DSL example)

```kotlin
// app/build.gradle.kts
android {
    defaultConfig {
        minSdk = 31          // QNN NPU requires it
        ndk { abiFilters += "arm64-v8a" } // NPU only on arm64
    }
    packaging { jniLibs { useLegacyPackaging = true } } // QNN .so requires
}

dependencies {
    // LiteRT main (2025 TFLite rebrand)
    implementation("com.google.ai.edge.litert:litert:1.0.1")
    implementation("com.google.ai.edge.litert:litert-gpu:1.0.1")

    // Qualcomm QNN NPU Delegate
    implementation("com.qualcomm.qti:qnn-runtime:2.34.0")
    implementation("com.qualcomm.qti:qnn-litert-delegate:2.34.0")

    // If using ONNX Runtime QNN (alt)
    // implementation("com.microsoft.onnxruntime:onnxruntime-android-qnn:1.24.3")

    // CameraX
    val camerax = "1.3.4"
    implementation("androidx.camera:camera-camera2:$camerax")
    implementation("androidx.camera:camera-lifecycle:$camerax")
    implementation("androidx.camera:camera-view:$camerax")

    // BLE (Nordic library strongly recommended over raw BluetoothGatt)
    implementation("no.nordicsemi.android:ble-ktx:2.7.5")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
```

### 4.3 NPU inference pseudocode

```kotlin
import com.qualcomm.qti.QnnDelegate
import org.tensorflow.lite.Interpreter

val qnnOptions = QnnDelegate.Options().apply {
    backendType = QnnDelegate.Options.BackendType.HTP_BACKEND
    htpPerformanceMode = "burst" // real-time CV uses burst; power-saving uses balanced
}
val qnnDelegate = QnnDelegate(qnnOptions)

val interpreterOptions = Interpreter.Options().apply {
    addDelegate(qnnDelegate)
    // LiteRT auto-fallbacks to CPU if QNN unavailable
}

val yoloInterp = Interpreter(loadModelFile("yolo11n_int8.tflite"), interpreterOptions)
val depthInterp = Interpreter(loadModelFile("depth_anything_v2_small_fp16.tflite"), interpreterOptions)
```

### 4.4 Manifest essentials

```xml
<uses-feature android:name="android.hardware.camera.any" android:required="true"/>
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true"/>

<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" tools:targetApi="31"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>

<service
    android:name=".NavigationService"
    android:foregroundServiceType="camera|connectedDevice"
    android:exported="false"/>
```

Android 12+ requires `foregroundServiceType` on FGS; 14+ runtime-checks: if you declare `camera` but haven't requested CAMERA runtime permission before service start, throws `SecurityException`. Common newbie pitfall.

---

## Staged Recommendations (Aligned with V0–V3)

The accepted V0 boundary is split into V0a and V0b in [v0-implementation-plan.md](../plan/v0-implementation-plan.md).

| Stage | Goal | Recommended approach |
|---|---|---|
| **V0a minimum closed loop** | Camera -> CPU TFLite YOLO -> TTS "person ahead" | One real device + Kotlin + LiteRT CPU/XNNPACK delegate. **Skip NPU for this slice**; run end-to-end first |
| **V0b corridor demo** | YOLO + Depth Anything -> geometric decision -> TTS | Switch to QNN Delegate to hit NPU; YOLO directly use Qualcomm AI Hub's W8A8 TFLite; Depth Anything use AI Hub's FP16 TFLite |
| **V1 audio privacy** | Add bone-conduction headset | Route Android TTS to Bluetooth audio; keep environmental sound open |
| **V2 BLE feedback + background persistence** | Connect Bangle.js 2 + bone-conduction headset; foreground Service for lock-screen running | Nordic BLE library + Foreground Service (type=camera\|connectedDevice); CompanionDeviceManager for "companion device" enhanced background permissions |
| **V3 smart glasses** | Video source switches from phone camera to glasses | Mentra Live / MentraOS: glasses connect to phone-side Mentra app over BLE, MentraOS Mini App (TypeScript independent backend process) subscribes to video stream, then pushes frames to our Kotlin app via local HTTP/WebSocket; Brilliant Frame: Python SDK in PC/phone background, similar bridge; Rokid: directly use Android/Kotlin, **same language as our project, near-zero migration** |
| **V4 (optional) iOS** | Cover iPhone users | Use Kotlin Multiplatform to factor out business logic; iOS rewrites in Swift + Core ML + Vision. **Long-term** |

**Key judgment:** in V0–V2, **set aside the "cross-platform" question entirely.** Make Android single-platform work first, then talk about iOS. Flutter / RN's cross-platform promises **cannot be honored** on this project's hardest points (NPU, BLE background, FGS type) — and force you to learn an extra framework layer.

---

## AI-Assisted Development Friendliness — Dedicated Assessment

This is the project's **decisive dimension**. Concrete strategy:

1. **First tool: Claude Code** (terminal agentic CLI), run directly in Android Studio's built-in Terminal. Can read logcat, edit Gradle, run `./gradlew assembleDebug`, see errors, self-iterate. Per Anthropic 2025-09-29: Sonnet 4.5 SWE-bench Verified 77.2%; 2025-11-24: Opus 4.5 hits 80.9% ("first model to exceed 80% threshold") — top-tier.
2. **Second: Cursor / VS Code + Claude / Gemini Code Assist** in Android Studio as code-completion. Android Studio's built-in Gemini also works.
3. **Language / framework LLM training-corpus ranking** (combining Sonnet 4.5 official notes + production experience):
   - JavaScript / TypeScript (Sonnet 4.5 official "stronger results"; most)
   - Python (official "stronger results," but mobile-Python corpus thin)
   - Kotlin (official "supports Kotlin"; Android official docs + Jetpack Compose samples plentiful)
   - Dart / Flutter (Sonnet series good coverage)
   - Swift (lower than above)
4. **Least-error AI combination:** Kotlin + Jetpack Compose + official AndroidX libraries. Fewest pitfalls.
5. **Common "AI hallucination" traps:**
   - Android 12+ BLE permission split (BLUETOOTH_SCAN / CONNECT replacing old BLUETOOTH) — AI occasionally writes old API.
   - Foreground Service Type 14+ strict check — AI occasionally forgets.
   - QNN delegate version match — `qnn-runtime` and `qnn-litert-delegate` versions must be identical.
   - CameraX frame analysis `setBackpressureStrategy(STRATEGY_KEEP_ONLY_LATEST)` must be on for real-time CV; else backlog explodes.
   - NPU delegate creation failure throws on `Interpreter` — must try-catch + fallback CPU.
6. **Prompting tips:**
   - Explicitly tell it "Android Studio Koala+, AGP 8.5+, Kotlin 1.9+, Jetpack Compose, targetSdk 34, minSdk 31" — version context cuts hallucination.
   - Have it **first generate Gradle dependency block and Manifest changes**, then business code — missing manifest permissions is the most common "code looks fine but crashes at runtime" cause.
   - Paste it logcat stacktrace, not symptom description.

---

## Risks and Pitfalls

1. **Depth Anything V2 has no off-the-shelf INT8** — Qualcomm AI Hub mobile only has FP16 (94.3 MB). If you need to squeeze more latency (e.g., 8 Gen 1 devices, or V3 glasses with higher on-device load), self-quantize via AI Hub Workbench `submit_quantize_job` PTQ — precision may drop.
2. **NNAPI officially deprecated** — Android NDK migration guide: *"The Neural Networks API (NNAPI) is deprecated. It was introduced in Android 8.1 … and deprecated in Android 15."* LiteRT new docs recommend CompiledModel API + vendor NPU Delegate (QNN/NeuroPilot) instead. **Don't** let AI write `NnApiDelegate(...)` legacy code.
3. **QNN delegate only supports arm64-v8a and INT8/FP16** — FP32 models must be quantized first or use GPU delegate.
4. **Foreground Service background persistence:** Android 12+ strictly limits FGS startup from background; this project starts FGS when user opens app and runs in foreground throughout — fine. But "auto-start on lock-screen" is nearly impossible; needs CompanionDeviceManager + connectedDevice type FGS for exemption.
5. **BLE compatibility on OEM ROMs:** Xiaomi / Huawei / Samsung have different battery policies; Bangle.js 2 connection stability recommends Nordic's `ble-ktx` over raw `BluetoothGatt` — avoids the swathe of mystery status=133 bugs.
6. **Real-device USB debugging cable:** many Type-C cables are charge-only, not data — produces the mysterious "adb devices sees nothing" issue. Keep an OEM cable handy.
7. **Apple Silicon Mac emulator:** use ARM64 image, newer (Ladybug+) AVDs are near-native, but **emulator cannot test NPU, cannot test Bluetooth, camera capability extremely limited** — all real functional validation on real devices.
8. **APK size:** QNN runtime native .so adds ~100+ MB, plus Depth Anything FP16 94.3 MB (Qualcomm AI Hub official "Model size (float)") — APK can bloat to 200+ MB. For Play Store, use Android App Bundle + Play Asset Delivery to ship models as on-demand assets.
9. **V3 multi-language reality:** MentraOS is a TypeScript backend service; this project's body is Kotlin app; they communicate via local HTTP / WebSocket — not a "stack mismatch" issue but normal "two processes, separate concerns." Don't force RN to "write the full stack in one language."
10. **Claude usage and cost:** heavy code-writing dependence. Per Anthropic 2025-09-29: Sonnet 4.5 official pricing **$3 per million input tokens, $15 per million output tokens** (not an estimate — published rate); mid-size MVP $50–150 total; budget accordingly.

---

## Appendix: First-Hour Startup Checklist

1. Download Android Studio Mac with Apple Silicon version, install.
2. First launch → SDK Manager → install Platform 34/35 + Build-Tools 34 + NDK + CMake + Android Emulator + an arm64-v8a system image.
3. New Project → Empty Activity (Compose) → set package name (e.g., `app.roana.android`) → minSdk 31.
4. Connect a Snapdragon 8 Gen 2+ real device via USB, allow debugging, `Run` Hello World.
5. Paste this doc's §4.2 Gradle dependency block, Sync.
6. Tell Claude Code in terminal: *"Read my build.gradle.kts and AndroidManifest.xml; add CameraX preview + LiteRT loading yolo11n.tflite CPU inference; draw detection boxes on preview."*
7. After that works, have it add QNN delegate.

At this point you're running YOLO on NPU. The rest is stacking features on the V0→V3 cadence.
