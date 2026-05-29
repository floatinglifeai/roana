# Web / PWA Route Evaluation

> Can we skip the Android Studio / Gradle / Kotlin toolchain by going pure-web (PWA) or local-server-on-phone? Answer: **no — not for this product**. This document records why, so future contributors don't re-explore the same dead ends.

---

## TL;DR

- **Direct answer: do NOT use pure PWA or Termux local-server to "skip Android Studio."** This project's three hardest things — **continuous camera stream, NPU acceleration, BLE background persistence** — are exactly where the web platform is weakest, where PWAs effectively die when backgrounded. The web route saves you on "packaging/UI" (which was never the hard part) while blowing up "real-time CV + always-on operation" (the actual hard problem) into a project-level risk.
- **Accepted project decision after review:** V0 implementation starts with **native Kotlin Android**, not web, PWA, or Capacitor. The native V0 boundary is recorded in [v0-implementation-plan.md](../plan/v0-implementation-plan.md). Capacitor remains a researched fallback if native development becomes blocked, but it is not the current implementation path.
- **Key judgment: Web/PWA NPU access is still vaporware in 2026.** Google Chrome engineer Reilly Grant on the blink-dev mailing list 2026-02-13: *"We've decided to exclude Android from the Origin Trial due to the implementation's immaturity on that platform. Since only CPU inference is supported on Android (GPU and NPU inference support is planned but incomplete)."* The Origin Trial re-enabled in M-147 on 2026-02-24 with **Android still excluded**. WebGPU has been stable on Android Chrome 121+ (2024-01) for Adreno/Mali but GPU-running Depth Anything V2-Small is still an order of magnitude slower than NPU. Web Bluetooth on Chrome for Android can connect to Bangle.js 2 but **tab-invisible may disconnect** — fatal for "continuous navigation."

---

## Key Findings

1. **WebNN (standard NPU API) on Android actually only has CPU backend in 2026.** webnn.io browser compatibility matrix shows Android uses `TFLite + XNNPACK CPU`; NPU/GPU delegates are optional, *"if a requested delegate (GPU/NPU) is missing or fails, execution transparently falls back to the XNNPACK CPU path."*
2. **WebGPU is on by default on Android Chrome 121+** (Adreno + Mali, Android 12+; Imagination GPU since Chrome 139), but on Depth Anything V2-Small (a ViT-S model), even desktop GPU only hits ~5 FPS; mobile expects to halve to 2–3 FPS.
3. **PWA backgrounded + screen off = stops** — this is browser-design "won't fix by design," not a versioned bug. `MediaStream` pauses, Wake Lock releases, Service Worker can't access camera — all stack.
4. **Web Bluetooth on Chrome for Android can connect Bangle.js 2, but the official Implementation Status doc states "No background scanning (tab must be visible on some browsers)";** GATT connection typically released when tab is hidden. iOS Safari completely unsupported.
5. **Termux route is dead-end on three points:** can't get camera video stream (only frame-by-frame photos via Activity, 10 FPS impossible); can't access NPU; killed in background by domestic ROMs.
6. **Capacitor (Ionic) is currently the best approximation of "skip 90% of native toolchain + keep all critical capabilities."** Mature plugins exist: camera-preview (real-time captureSample), bluetooth-le (with Android foreground service persistence), android-foreground-service, reference `dust-onnx-capacitor` (with NNAPI/XNNPACK/CPU AcceleratorSelector), etc.
7. **Tauri 2 Mobile not recommended now:** Tauri 2.0 stable shipped 2024-10-02, but Tauri team's own 2.0 RC blog: *"We see improvements to be made in the development experience for mobile and we acknowledge that not all of our desktop features and plugins are ported or available on mobile yet."* Mobile plugin ecosystem (NFC, Barcode, Biometric, Haptics, Geolocation) insufficient for real-time CV + BLE foreground service combo.

---

## Details

### One — Three Routes Overall

#### Route B — Pure PWA (in-browser WebRTC + TF.js/ORT Web)

**Good for:** algorithm prototype, desktop browser demo, short daytime indoor testing.
**Bad for:** users handheld-using their phone for long-time outdoor navigation as a shipped product.

##### B.1 Camera capture
- `getUserMedia({ video: { facingMode: { exact: "environment" } } })` works for rear camera on Android Chrome (stable since Chrome 66);
- But **can't stably distinguish "main / wide / tele / macro"** — Chromium discussion shows devs can only enumerate devices and guess via label substring "back/wide/macro" — no API-level guarantee;
- Resolution / framerate controllable via `width/height/frameRate` constraints but actual output is browser-negotiated;
- **Fatal:** when tab backgrounded or screen off, `MediaStream` pauses. Even with Wake Lock API (Chrome 84+), MDN explicit: *"If the user minimizes a tab, closes a window, or navigates away from the PWA in which a screen wake lock is active, the lock will be released automatically."*

##### B.2 In-browser inference

| Backend | Status (2026.05) | Expected on our models |
|---|---|---|
| **TF.js WebGL** | Mature but old, no compute shaders | YOLO11n barely 10 FPS on desktop, Depth Anything V2-S single-digit FPS |
| **TF.js WebGPU** | Available, scheduling weaker than ORT Web | Better than WebGL, weaker than ORT Web WebGPU |
| **ONNX Runtime Web WASM (SIMD+threads)** | Most stable "fallback" path 2025-2026 | YOLO11n a few FPS on desktop Chrome; mobile slower; PyImageSearch tutorials only claim "smoother user experience" without FPS numbers |
| **ONNX Runtime Web WebGPU** | Default-on Android Chrome 121+ (2024-01, Adreno/Mali) | **Currently the fastest publicly-available path;** community Xenova webgpu-realtime-depth-estimation demo + Depth Anything V1 desktop tweets report "under 200 ms" ≈ 5 FPS, **no credible Android Chrome FPS data exists** — that itself is a red flag |
| **WebNN (standard NPU API)** | **Explicitly disabled on Android** (see Reilly Grant quote above) | Even with flag enabled, Android backend uses TFLite + XNNPACK CPU; NNAPI delegate optional and falls back to CPU if missing. **NNAPI itself deprecated in Android 15** (Android NDK official migration guide: *"The Neural Networks API (NNAPI) is deprecated. It was introduced in Android 8.1 to provide a unified interface for hardware accelerated inference for on-device machine learning, and deprecated in Android 15."*) |

**Performance reality:**
- Closest verifiable data point to your "native NPU 13–28 FPS" claim is AXERA AX650 NPU running Depth Anything V2-Small (518×518 vits) at **33.25 ms ≈ 30 FPS** (HuggingFace AXERA-TECH/Depth-Anything-V2 model card);
- Reference comparison — Snapdragon X Elite laptop NPU running YOLOv8s INT8 in Kartikey Rawat's Medium piece "Unleashing the Beast: Running YOLOv8 on Snapdragon X Elite NPU at 65 FPS" reports *"achieving 65+ FPS on the NPU, compared to barely 2 FPS on the CPU"* (~29× speedup);
- Qualcomm AI Hub's Depth-Anything V2 page **currently lacks per-device latency data** (page says "Not supported on any chipset"), only V1 has old record (cs_8275 / Android 14 / TFLite / NPU 646 ops, 889.2 ms);
- **Conclusion: hitting "YOLO + segmentation + Depth at simultaneous 10–15 FPS" on the pure PWA route, even on a Snapdragon 8 Gen 3 flagship, even with WebGPU fully on, expected actual is 2–6 FPS**, with high heat and battery drain.

##### B.3 PWA hardware access

| Capability | Status |
|---|---|
| **Camera** (foreground, screen on) | ✅ getUserMedia |
| **Camera** (screen off / background) | ❌ MediaStream pauses |
| **Web Bluetooth → Bangle.js 2** | ✅ Chrome for Android 56+, HTTPS + user gesture to trigger `requestDevice()` required |
| **Web Bluetooth background persistence** | ⚠️ Web Bluetooth CG implementation-status.md: *"No background scanning (tab must be visible on some browsers)";* GATT connection usually released when tab hidden |
| **iOS Web Bluetooth** | ❌ Safari unsupported, need Bluefy / WebBLE alt browsers — detour |
| **Web Speech API SpeechSynthesis (TTS)** | ✅ Android Chrome works, voice quality depends on system TTS; Chinese voice unconfigurable in detail |
| **DeviceMotion / DeviceOrientation (IMU)** | ✅ but HTTPS + permission; ~60 Hz |
| **Wake Lock** (prevent screen off) | ✅ Chrome 84+, **only effective while document visible**, releases on minimize |
| **PWA install-to-home-screen** | ✅ Chrome for Android "Add to Home Screen," no store upload needed |
| **Service Worker running ML inference** | ⚠️ SW can't access MediaStream; lifecycle browser-controlled; cannot be used as "always-on background inference service" |

##### B.4 Fatal problem: background continuous operation

PWA's design philosophy **doesn't allow web pages to do heavy lifting in background** — browsers necessarily so for battery and anti-abuse. Edana PWA vs Native comparison summed it bluntly: *"Example: an infrastructure operator wanted to capture images at fixed intervals for automatic surveying. The PWA failed whenever the browser went to the background, requiring a native solution for process reliability."*

For a **navigation-assistance app** this means:
- User puts phone in pocket (screen off) → camera stops → inference stops → BLE disconnects → vibration watch receives no direction → **navigation interrupted**;
- User takes a phone call then switches back → PWA may have been reaped by browser; need to reinitialize models (Depth Anything V2-Small ONNX ~25 MB, takes seconds);
- In this usage pattern, pure PWA is **unusable**.

---

#### Route C — Local Python/Node Server on Phone + HTML Frontend

**Conclusion: dead end.**

##### C.1 Termux path

Termux is an excellent Android terminal + Linux subsystem; can install Python, PyTorch CPU, ONNX Runtime CPU. But for this project, three blockers:

1. **Termux can't get camera video stream.** Termux:API's `termux-camera-photo` takes **one photo** at a time (spawns Camera Activity, returns JPEG), can't read continuous frames. Termux GitHub Discussion #8456 maintainer explicit: *"No, this is not possible. You can't access camera device through /dev. Even if can, there could be some proprietary protocol (Android doesn't use open source camera drivers)."* Android's Camera2/CameraX is Java/Kotlin; Termux's Linux process has no Android Permission and no Surface, can't connect at all. Each photo goes through IPC starting Activity, hundreds of ms latency — 10 FPS impossible.
2. **Termux can't access NPU.** NNAPI/QNN are Android NDK APIs; Termux's PyTorch/ONNX Runtime are ordinary Linux binaries running CPU.
3. **Termux killed in background.** Android OEMs (Xiaomi, Huawei, OPPO, Vivo) extremely hostile to background processes; require user-manual whitelist — unacceptable extra step for visually-impaired users.
4. **Termux removed from Google Play** (maintainer voluntarily, since Play security policies conflict with termux-api model); users go to F-Droid / GitHub for Termux + Termux:API — very unfriendly to blind users.

##### C.2 Node.js same issue, ecosystem narrower (only Termux / Nodejs-mobile on Android).

##### C.3 Even if you stitched it together, complexity introduced (IPC, HTTP/WebSocket, CORS, HTTPS self-signed cert, Termux startup script, Android background whitelist) **far exceeds** Android Studio + Capacitor.

---

#### Route D — WebView Hybrid (Capacitor etc.) — Recommended Compromise

Capacitor is the Ionic team's modern rewrite of Cordova: write a Web App (HTML/JS/CSS), `npx cap add android` packages it as a native .apk, native capabilities exposed via plugins (Java/Kotlin/Swift) as JS bridges.

##### D.1 The capabilities you want, Capacitor has off-the-shelf plugins:

| Need | Plugin | Note |
|---|---|---|
| **Rear camera real-time frame** | `@capacitor-community/camera-preview` (Capacitor 8 maintained branch) / `@capgo/capacitor-camera-preview` / `michaelwolz/capacitor-camera-view` | Native CameraX impl; provides `captureSample(quality)`, README: *"Captures a sample image from the video stream. … This can be used to perform real-time analysis on the current frame in the video."* |
| **BLE → Bangle.js 2** | `@capacitor-community/bluetooth-le` / `@capgo/capacitor-bluetooth-low-energy` / `@capawesome-team/capacitor-bluetooth-low-energy` | All native BluetoothGatt; latter two support **Android foreground service** persistence (docs: *"Start a foreground service to maintain BLE connections in background (Android only)"*) |
| **Android foreground service** (lets app continue running backgrounded / locked) | `@capawesome-team/capacitor-android-foreground-service` | Shows persistent notification, process not killed by system; this is **the only compliant solution** for Android background persistence |
| **ONNX Runtime + NNAPI/XNNPACK acceleration** | `rogelioRuiz/dust-onnx-capacitor` (open-source reference impl on GitHub) | README: *"AcceleratorSelector.kt # EP selection (NNAPI/XNNPACK/CPU)"* |
| **TFLite** | No official Capacitor TFLite plugin yet (capacitor-community/proposals#82 still open); need to write a thin plugin wrapping onnxruntime-android or tflite-task-vision | Medium complexity |
| **TTS** | `@capacitor-community/text-to-speech` or directly Web Speech API (works in WebView) | |
| **IMU** | `@capacitor/motion` | DeviceMotion upgrade |

##### D.2 Capacitor's real cost
- ✅ **You spend 95% of time writing HTML/JS**, AI (Claude) writes very smoothly, fits the founder profile;
- ✅ **Completely avoids writing a full Kotlin app from scratch** — don't need to understand Activity lifecycle, Fragments, ViewModels, Jetpack Compose;
- ⚠️ **You still need Android Studio + JDK + Gradle installed** (to build the native shell); occasionally need to edit `AndroidManifest.xml` (permissions) and `build.gradle` (dependencies);
- ⚠️ Native-side crashes show error in Android Studio Logcat; you still need to read stack traces;
- ⚠️ If you need "inference on native side, results passed to JS for rendering" (the optimal architecture for performance), you need to write a simple Capacitor plugin, at which point you touch some Kotlin. Have AI give you 50-line template.

##### D.3 Performance expectation
Capacitor + ONNX Runtime Android (with NNAPI EP) + camera-preview captureSample mode:
- YOLO11n + Depth Anything V2-Small on Snapdragon 8 Gen 2/3 expected **8–15 FPS** (reference arXiv 2511.13453 YOLO11n LiteRT on Galaxy Tab S9 / Snapdragon 8 Gen 2 same-class benchmark);
- Same order of magnitude as "pure native Kotlin + LiteRT";
- **Key: model inference on native thread, UI/JS completely non-blocking.**

---

#### Route E — Tauri 2 Mobile (NOT RECOMMENDED FOR NOW)

Tauri 2.0 stable shipped 2024-10-02 (v2.tauri.app/blog/tauri-20/, by Tillmann Weidinger; Wikipedia independent corroboration), added Android/iOS support. But Tauri team's own 2.0 RC blog (v2.tauri.app/blog/tauri-2-0-0-release-candidate/, 2024-08-01) admits: *"We see improvements to be made in the development experience for mobile and we acknowledge that not all of our desktop features and plugins are ported or available on mobile yet."* Mobile plugin ecosystem currently NFC, Barcode Scanner, Biometric, Haptics, Geolocation — **no mature combo of Camera Preview + real-time frame + BLE foreground service + ONNX acceleration**. And Tauri writes native in Rust — for a zero-mobile-experience founder relying on Claude, **Rust + JNI learning curve is steeper than Kotlin**.

---

### Two — Capability-by-Capability Comparison

| Capability | Pure PWA (B) | Termux server (C) | Capacitor (D) | Native Kotlin |
|---|---|---|---|---|
| **Rear camera real-time frame (30 FPS)** | ✅ getUserMedia | ❌ can't get video stream | ✅ camera-preview captureSample | ✅ CameraX |
| **Background/lock-screen camera+inference** | ❌ MediaStream pauses, Wake Lock loses | ⚠️ process killed by OEM | ✅ foreground service plugin | ✅ foreground service |
| **NPU acceleration** | ❌ Android WebNN currently CPU-only | ❌ | ✅ ONNX Runtime + NNAPI EP (NNAPI deprecated A15 but LiteRT/QNN/ExecuTorch still work via plugin) | ✅ LiteRT/QNN/ExecuTorch direct |
| **GPU acceleration** | ✅ WebGPU Android Chrome 121+ (Adreno/Mali) | ❌ | ✅ ONNX Runtime GPU EP (OpenCL/Vulkan delegate) | ✅ |
| **Expected YOLO11n + Depth V2-S combined FPS** | 2–6 FPS (WebGPU max) | 1–3 FPS (CPU only, framerate IPC-limited) | 8–15 FPS | 13–30 FPS (NPU) |
| **BLE → Bangle.js 2** | ✅ Web Bluetooth (Chrome 56+) | ⚠️ termux-api limited | ✅ Capacitor BLE | ✅ |
| **BLE background persistence** | ❌ disconnects on tab hide | ⚠️ process may be killed | ✅ foreground service | ✅ |
| **TTS Chinese** | ✅ Web Speech API (depends on system engine) | ⚠️ termux-tts stutters | ✅ capacitor-tts or Web Speech | ✅ TextToSpeech |
| **Non-store distribution** | ✅ Add to Home Screen | ✅ no distribution | ✅ APK sideload / self-signed | ✅ APK sideload |
| **iOS simultaneously (better-to-have)** | ⚠️ iOS Safari no Web Bluetooth, PWA install restricted | ❌ | ✅ same JS builds iOS | ❌ rewrite |
| **AI (Claude) code-writing friendliness** | ⭐⭐⭐⭐⭐ (pure Web) | ⭐⭐⭐ (rare path, AI corpus thin) | ⭐⭐⭐⭐ | ⭐⭐⭐ (Kotlin AI familiar) |
| **Learning curve (zero mobile exp)** | Extremely flat | Steep (Linux+Android boundary issues) | Medium (need to know a little Gradle/Manifest) | Steep |
| **Can fully skip Android Studio/Gradle** | ✅ | ✅ | ❌ (need SDK + build, but 95% code is JS) | ❌ |

---

### Three — "Skip Toolchain" Saved vs Newly Introduced Complexity

#### What you think you skipped:
- Learning Kotlin (**reality:** Claude writes Kotlin fine; ViewBinding/Compose AI corpus is large — not much real saving).
- Learning Gradle config (**reality:** on Capacitor you still touch `build.gradle` for dependencies, just less).
- Installing Android Studio (large IDE) (**reality:** even on PWA, you eventually install it for adb debugging or PWA→TWA packaging).

#### Pure Web newly introduced complexity (easily underestimated):
1. **HTTPS self-signed cert:** Web Bluetooth, getUserMedia, Wake Lock, Service Worker all require secure context. Local server route requires mkcert self-sign + user trust, or ngrok reverse-proxy — more hassle than signing one APK.
2. **Background persistence "hack":** community has NoSleep.js (continuously play hidden video to fool system), but **doesn't solve the camera-pause core problem**.
3. **WebGPU shader debugging:** debugging WebGPU shaders on Android Chrome is far inferior to desktop DevTools; different GPUs (Adreno vs Mali) behave differently.
4. **Model loading cold start:** every PWA start re-downloads / reinitializes 25 MB Depth Anything V2-Small ONNX, much slower than native app with bundled .tflite; using Cache API / IndexedDB adds code.
5. **Web Bluetooth UI friction:** every `requestDevice()` requires user gesture and pops Chrome's native device chooser — extremely unfriendly to blind users.
6. **No NPU:** you said "NPU is better-to-have not must-have," but reality is your performance target (10–15 FPS simultaneously running three models) **cannot be hit without NPU**.

#### Net account:
- **Pure PWA route: 30% save in setup for 200% in runtime pitfalls — not worth it.**
- **Capacitor route: 20% extra setup (one-time Gradle/AndroidManifest) for 90% functional fidelity — worth it.**

---

### Four — AI (Claude) Code-Writing Angle

| Route | AI friendliness | Main "pitfalls" |
|---|---|---|
| Pure PWA | Extremely high. getUserMedia, TF.js/ORT Web, Web Bluetooth all common in LLM training | AI happily gives "it runs" code but **doesn't proactively flag background-stops** — you discover it week 3 of testing |
| Termux server | Low. Sparse and outdated material | AI prone to hallucinating "termux-camera can grab video stream" |
| **Capacitor** | **Medium-high.** Community docs complete, Claude familiar with `capacitor.config.ts`, AndroidManifest, Gradle common changes | AI occasionally suggests deprecated plugin versions (e.g., v2 vs v6) |
| Native Kotlin | Medium. Android material massive, but API changes fast; Claude occasionally gives Android 8-era BLE patterns | Logcat errors are clear enough for AI iteration |

**For our founder profile (zero mobile experience + heavy AI dependence): Capacitor is the sweet spot.** Most work is in JS/TS where AI is rock-solid; only when you need a custom ONNX plugin do you touch Kotlin.

---

## Recommendations

These recommendations are retained as fallback analysis. They are **not** the accepted V0 path.

### Fallback Phase 0: pure-web feasibility demo
- **Goal:** verify YOLO11n + Depth Anything V2-Small output is reasonable for our decision layer (depth map → direction commands);
- **Stack:**
  - A static HTML + single-file JS using `@huggingface/transformers` or `onnxruntime-web@dev`;
  - YOLO11n ONNX (quantized ~3 MB) + Depth Anything V2-Small ONNX `q4f16` quantized (~18 MB, HF onnx-community/depth-anything-v2-small);
  - `getUserMedia({ video: { facingMode: "environment" } })`;
  - **On Apple Silicon Mac** with Chrome (M-series WebGPU is 10× faster than phone), validate algorithm logic first;
- **No need for:** Bluetooth, TTS, background. This phase only checks "can the model output drive useful decisions."
- **Trigger to next phase:** algorithm logic works; or FPS even on Mac drops below 5 → consider smaller model or crop input to 252×336 (reference Luxonis RVC4 vit-s-336x252 variant).

### Fallback Phase 1: Capacitor MVP
- **Goal:** "usable" version on Android phone — can walk for 5 minutes, watch vibrates correct direction, TTS reads directions;
- **Stack:**
  - Capacitor 6+ (Capacitor 8 latest);
  - Vue/React/Svelte (or vanilla — AI writes vanilla fine too);
  - `@capacitor-community/camera-preview` (gets video stream, captureSample pulls frames);
  - **First step:** use `onnxruntime-web` + WebGPU in WebView to run models — **lets you reuse phase-0 code**;
  - **Second step** (if FPS insufficient): fork `dust-onnx-capacitor` or write a Capacitor ONNX plugin wrapping `onnxruntime-android`, switch to NNAPI EP / XNNPACK, target 10+ FPS;
  - `@capacitor-community/bluetooth-le` connects Bangle.js 2;
  - `@capawesome-team/capacitor-android-foreground-service` adds persistent notification;
  - Web Speech API for TTS.
- **Key decision threshold:**
  - End of week 1 test: can pure web inference + Capacitor camera-preview hit ≥5 FPS on target device and feel acceptable? If yes → don't change;
  - Otherwise: spend a week on a native plugin, switch to NNAPI/GPU delegate, target ≥10 FPS.

### Fallback Phase 2: decide whether to fall back to native based on real user feedback
- If Capacitor runs stable, **stay on Capacitor** — many shipped products (medical, sports apps) use Capacitor;
- Only fall back to pure Kotlin when Capacitor framework-level bugs hit, or when you need hardware features no plugin supports (Camera2 RAW, ML Kit Vision pipeline).

### Fall-back trigger
- Does your expected usage pattern truly require "screen off + in pocket"? If your scenario is **phone-held + bone-conduction headset** (screen stays on), pure PWA might survive — but still limited by BLE background, model cold-start, etc. **Suitable only for tech demo or self-use; not for distribution to visually-impaired users.**

---

## Caveats

1. **WebNN "looks great" trap on Android:** articles and Microsoft Learn docs say "WebNN supports NPU acceleration" — **that's on Windows.** Chromium team 2026-02 explicit: Android WebNN currently **CPU-only**, "GPU and NPU support planned but incomplete." **Do not select on WebNN.**
2. **NNAPI deprecation:** Google deprecated NNAPI in Android 15 (Android NDK official migration: *"The Neural Networks API (NNAPI) is deprecated. It was introduced in Android 8.1 ... and deprecated in Android 15"*, recommended migration to TensorFlow Lite in Play Services / AICore). Affects `react-native-fast-tflite` etc. (README literally: *"NNAPI is deprecated on Android 15. Hence, it is not recommended in future projects."*). New code should use LiteRT GPU delegate or vendor NPU SDK (Qualcomm QNN, MediaTek NeuroPilot).
3. **Web Bluetooth device chooser UX:** Chrome forcibly pops system BLE device chooser; **visually-impaired users cannot bypass this step** (system accessibility can read but flow remains complex). Native BLE lets you manage paired devices yourself.
4. **getUserMedia can't pick specific wide/ultra-wide lenses:** wide-angle is more visually-impaired-friendly (larger FOV). Web `MediaTrackConstraints` has **no standard way** to pick a specific physical lens; native CameraX can.
5. **iOS Safari no Web Bluetooth** — if cross-platform later, Capacitor lets you ship iOS from one JS source; pure PWA stuck on BLE step on iOS.
6. **iOS PWA political risk:** Apple in iOS 17.4 beta 2 (2024-02-15, MacRumors) briefly disabled PWA home-screen-install for EU users (DMA-compliance overreaction), reversed 2024-03-01, official statement: *"We have received requests to continue to offer support for Home Screen web apps in iOS, therefore we will continue to offer the existing Home Screen web apps capability in the EU."* Even so, **iOS PWA has always been the area Apple least wants to support** — putting your lifeline on PWA is a hazard.
7. **Model size + cold start:** 25 MB ONNX downloads / compiles on every first start. Phone offline → you must write your own PWA IndexedDB caching policy. Capacitor APK bundles model in assets, available on start.
8. **TTS interruption:** Web Speech API SpeechSynthesis stability varies massively across Android TTS engines (Google TTS vs Samsung TTS vs Xiaomi TTS), **frequently cancels for no reason.** Native `TextToSpeech` has finer callbacks.
9. **Termux Google Play removal:** users need F-Droid for Termux + Termux:API — unacceptable for visually-impaired users; further kills route C.
10. **Tauri Mobile in 2026 still Rust + immature plugin ecosystem,** don't choose.
11. **"Web-side Depth Anything V2-Small mobile FPS = 2–6" in this report is extrapolated from desktop public data** ("under 200 ms ≈ 5 FPS"); **no credible "Android Chrome V2-S WebGPU FPS" benchmark exists.** That itself is a strong signal of immaturity; in phase 0 measurement, retain ±50% uncertainty on this number.

---

## Final One-Liner

> **For V0 implementation, use native Kotlin Android as decided in the decision log and [v0-implementation-plan.md](../plan/v0-implementation-plan.md). If native implementation becomes blocked, Capacitor is the only web-adjacent fallback worth reconsidering; pure PWA and Termux remain unsuitable for this product.**
