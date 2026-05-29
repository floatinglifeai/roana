# Roana On-Device ML Acceleration Strategy — iOS Core ML and Android NPU Landscape

> Cross-platform on-device inference strategy for Roana's per-frame model stack
> (Depth Anything V2-Small + YOLO11n), covering the iOS Core ML / Apple Neural
> Engine path and a layered Android NPU strategy. Informs the iOS port
> ([../plan/ios-port-plan.md](../plan/ios-port-plan.md)) and revisits the
> Android acceleration decision in [02-tech-stack.md](02-tech-stack.md).

**Status:** research / updated 2026-05-30.
**Audience:** engineering, platform decision-makers.
**Next update trigger:** on-device benchmarks on the iPhone 17 Air dev unit and a
flagship Snapdragon device; any LiteRT Next / ONNX Runtime QNN / ExecuTorch
major release.

---

## TL;DR

- **For iOS, ship Core ML directly.** Apple's `apple/coreml-depth-anything-v2-small`
  (F16) runs Depth Anything V2-Small in ~31-34 ms on Neural Engine across
  iPhone 12 Pro Max through iPhone 15 Pro Max, and the A18/A19-class Neural
  Engine on iPhone 16/17 is at minimum as fast — comfortably hitting the
  15-30 FPS Roana safety floor with YOLO11n (sub-5 ms) added on top.
  Engineering cost is the lowest of any platform: one runtime (Core ML), one
  accelerator (ANE), one published `mlpackage`.
- **For Android, adopt a two-tier layered strategy:** (i) **LiteRT Next with the
  new QNN and NeuroPilot accelerators (both productionised Nov-Dec 2025)** as
  the portable fallback covering Qualcomm + MediaTek + GPU/CPU with one
  `CompiledModel` API; (ii) **Qualcomm AI Hub pre-compiled context binaries
  (QNN HTP) as the flagship Snapdragon fast path**, where measured TFLite/QNN
  performance on Snapdragon 8 Elite Gen 5 is 31.5 ms for Depth Anything
  V2-Small and 0.73 ms for YOLO11n — i.e. >30 FPS headroom. Do **not** rely on
  Xiaomi MACE (abandoned since Jan 2022), Samsung Neural SDK (no longer offered
  to third parties), or NNAPI (deprecated in Android 15).
- **The single biggest 2025-2026 change is Google's LiteRT Next:** it replaces
  the old TFLite QNN/NeuroPilot delegates with a unified `CompiledModel` API and
  shipped first production NPU integrations on 2025-11-24 (Qualcomm) and
  2025-12-08 (MediaTek). This is the "newer, more universal, more
  actively-maintained acceleration library" we were looking for on Android — it
  is the right portable layer for Roana going forward.
- **Current local Snapdragon 8 Gen 2 evidence points below model compatibility.**
  On Xiaomi `2211133C` / SM8550 (`kalama`), the legacy TFLite QNN delegate
  reports HTP FP16 and quantized capability, but full logcat shows
  `QnnDsp loadRemoteSymbols failed`, `Failed to create transport for device`,
  `Failed to load skel`, and `Transport layer setup failed: 14001` before either
  YOLO11n or Depth Anything can prove operator compatibility. Treat packaging,
  QNN runtime/skel layout, signing/unsigned-PD setup, and delegate options as
  the current root-cause track. Do not tune CPU fallback performance until this
  transport layer is explained.

---

## Key Findings

1. **Depth Anything V2-Small is the binding constraint on every platform.** It is
   a 24.7 M-parameter DPT/DINOv2 model at 518x518 (or 518x392 in Apple's
   package), and on every measured silicon platform its inference time is
   30-55 ms — i.e. the model alone consumes essentially the entire 15-30 FPS
   budget. YOLO11n is ~1-5 ms everywhere on NPU and effectively free; it does
   not need fast-path optimisation.

2. **Apple iPhone 17 / A19 Pro / Neural Engine: comfortably in spec, but no
   public DepthAnythingV2 benchmark above A17.** Apple's published Core ML
   latencies are 31.10 ms (iPhone 12 Pro Max, iOS 18) and 33.90 ms (iPhone 15
   Pro Max, iOS 17.4). There is no Apple-published or independent benchmark for
   iPhone 16 Pro (A18 Pro) or iPhone 17 / 17 Pro / 17 Air (A19 / A19 Pro) on
   this exact model. Argmax's "iPhone 17" benchmark report (Sep 21 2025) notes
   the Neural Engine improved only ~25 % for the same workloads gen-over-gen
   while GPU jumped 2.5-3.1x. Applying ~1.15x ANE perf over A18 Pro to the
   33.9 ms iPhone 15 Pro Max baseline yields an **estimated 25-30 ms on
   iPhone 17 Air / A19 Pro** for Depth Anything V2-Small. With YOLO11n at
   <=5 ms, total per-frame model compute is ~30-35 ms ⇒ **28-33 FPS** before
   pre/post-processing.

3. **iPhone 17 Air thermals are a real but manageable risk.** The Air uses A19
   Pro (5-core GPU, no vapor chamber, "Copper Post" thermal design) versus the
   Pro/Pro Max's vapor chamber. Reviews report the Air reaches uncomfortable
   surface temperatures faster than the Pro under sustained load and uses
   thermal mass rather than active spreading; for a 20-30 min walking session,
   Roana should monitor `ProcessInfo.thermalState` and drop to 10 FPS / lower
   resolution on `.serious` / `.critical`.

4. **Android Snapdragon 8 Elite Gen 5 on QNN HTP comfortably exceeds the safety
   floor.** From the Qualcomm AI Hub published performance table for
   `qualcomm/Depth-Anything-V2`: TFLITE NPU float = **31.521 ms** on 8 Elite
   Gen 5, **35.628 ms** on 8 Elite for Galaxy, **50.806 ms** on 8 Gen 3.
   YOLO11n TFLITE w8a8 = **0.728 / 0.831 / 1.105 ms** on the same three SoCs.
   Combined per-frame model budget on 8 Elite Gen 5 is therefore ~32 ms ⇒
   ~31 FPS theoretical; even on Snapdragon 8 Gen 3 you get ~52 ms ⇒ ~19 FPS,
   still above the 10 FPS floor.

5. **LiteRT Next is the answer to "what is the newer, more universal acceleration
   library on Android?".** Google productionised the LiteRT Qualcomm AI Engine
   Direct (QNN) Accelerator on 2025-11-24 and the LiteRT NeuroPilot Accelerator
   (MediaTek) on 2025-12-08. Both replace the old TFLite QNN/NeuroPilot
   delegates with a single C++/Kotlin
   `CompiledModel(env, "model.tflite", HwAccelerator::kNpu)` API and Google
   Play "AI Pack" (PODAI) distribution of vendor compilers/runtimes. Per the
   Google Developers Blog (Nov 24 2025), the NPU path supports 90 LiteRT ops,
   allows 64 of 72 canonical models to delegate fully to the NPU, and runs
   "over 56 models in under 5ms with the NPU". This is the lowest-friction
   portable layer that exists today on Android.

6. **Several once-promising portable runtimes are dead-ends for Roana:**
   - **Xiaomi MACE:** last release v1.1.1 was 2022-01-13, with master commits
     trailing off in early 2022. The project is **effectively abandoned**. Do
     not use.
   - **Android NNAPI:** deprecated in Android 15; Google's own NNAPI Migration
     Guide states they "expect the majority of devices in the future to use the
     CPU backend" and recommends migrating to LiteRT.
   - **Samsung Neural SDK:** Samsung's developer-site banner states the SDK is
     "no longer provided to third-party developers". Use the `Samsung/ENNDelegate`
     GitHub project or LiteRT GPU delegate instead.

7. **Vendor-specific fast paths remain useful on flagship Snapdragon.** Qualcomm
   AI Hub lets you pre-compile Depth Anything V2 / YOLO11 to a "context binary"
   for a known SoC (e.g. SM8850 for 8 Elite Gen 5), eliminating on-device
   compile time and squeezing a few more ms versus on-device LiteRT
   compilation. For Roana's "premium device tier", this is worth the extra
   engineering cost; for everything else, LiteRT Next is enough.

8. **ExecuTorch (PyTorch) is rising fast but is not yet the right primary stack
   for Roana.** ExecuTorch 1.0 (October 2025) transitioned out of beta with
   production Apple Core ML, Qualcomm QNN, MediaTek NeuroPilot, a new Samsung
   Exynos backend (60 operators), Vulkan, and XNNPACK backends — arguably the
   only single framework spanning all the silicon Roana cares about. But for a
   vision app already on LiteRT/TFLite with a `.tflite` Depth Anything V2 model,
   switching to a PyTorch `.pte` flow has migration cost that LiteRT Next (which
   already understands the existing model) avoids. Re-evaluate in 2026 H2.

9. **Local SM8550 testing has not yet reached the model-operator question.** The
   phone-side QNN smoke gate now separates metadata/delegate errors from native
   DSP transport failures. On the Xiaomi Snapdragon 8 Gen 2 device, both the
   quantized YOLO11n model and FP32 Depth Anything model fail after the same
   native transport/skeleton setup errors, so the immediate question is whether
   the app is packaging and invoking QAIRT/QNN correctly on this device. Only
   after transport succeeds should op coverage, tensor layout, and quantization
   be treated as the primary suspects.

---

## PART A — iOS / Apple

### A.1 Depth Anything V2-Small on Apple Neural Engine: measured latency

Apple publishes Core ML benchmarks for `apple/coreml-depth-anything-v2-small`
on the Hugging Face model card:

| Device | iOS / macOS | Latency (ms) | Compute unit | FPS (model alone) |
|---|---|---|---|---|
| iPhone 12 Pro Max | iOS 18.0 | **31.10** | Neural Engine | ~32 |
| iPhone 15 Pro Max | iOS 17.4 | **33.90** | Neural Engine | ~30 |
| MacBook Pro M1 Max | macOS 15.0 | 32.80 | Neural Engine | ~30 |
| MacBook Pro M3 Max | macOS 15.0 | 24.58 | Neural Engine | ~41 |

**Important nuance:** Apple's `mlpackage` is configured for **518x392** input
(landscape COCO-like), not the 518x518 you would see on Qualcomm AI Hub —
slightly cheaper. The variant is Float16 (49.8 MB), with absolute relative error
0.0089 vs 0.0072 for the F32 version.

**A18 Pro / A19 / A19 Pro extrapolation.** Apple has not published Depth Anything
V2 numbers for iPhone 16 Pro or iPhone 17 / 17 Pro / 17 Air. Indirect evidence
(Argmax, Sep 21 2025): the Neural Engine gained only ~25 % gen-over-gen for
typical workloads while GPU jumped 2.5-3.1x, so for an ANE-bound model like DPT,
A19/A19 Pro is approximately **flat to ~15 % better** than A18 Pro and ~25 %
better than A17 Pro. Applying that to the 33.9 ms iPhone 15 Pro Max baseline
yields an **estimated 25-30 ms on iPhone 17 Air / A19 Pro**. With YOLO11n at
<=5 ms, total per-frame compute is ~30-35 ms ⇒ **28-33 FPS** before
pre/post-processing.

This is an **estimate**, not a measurement; verify on-device with the existing
Apple `mlpackage` and the iPhone 17 Air dev unit, logging
`CFAbsoluteTimeGetCurrent()` deltas around each `VNCoreMLRequest.perform`.

### A.2 YOLO11n → Core ML export gotchas

`yolo export format=coreml nms=True` from Ultralytics produces an `mlpackage`
that **does** wrap NMS as a Core ML pipeline model, but historically the result
does **not** automatically map to Vision's `VNRecognizedObjectObservation` for
*all* exports (Ultralytics issues #13794, #14668, #16927; Apple developer forum
thread 718551). The pattern that works most reliably:

1. **Use `nms=True` and `imgsz=640`** (square) so the pipeline embeds NMS and the
   model declares standard 640x640 input. Vision then returns
   `VNRecognizedObjectObservation` with `boundingBox` in normalised image coords.
2. **Inject IoU/confidence thresholds via `MLFeatureProvider`** at runtime rather
   than at export (the `ThresholdProvider` pattern with `iouThreshold` /
   `confidenceThreshold` `MLFeatureValue`s) so you can tune without re-exporting.
3. **Set `request.imageCropAndScaleOption = .scaleFill`** (or `.scaleFit` with
   explicit letterbox correction); `.centerCrop` drops content the network needs.
4. **INT8 vs FP16 on ANE:** YOLO11n (~2.6 M params) is already <5 ms in FP16 on
   ANE. INT8 (W8A8) compiles and runs on the Neural Engine in iOS 17+, but with
   negligible latency win and a measurable mAP drop for this tiny model.
   **Recommend FP16 on ANE for YOLO11n.**

If you hit the legacy "returns `VNCoreMLFeatureValueObservation` instead of
`VNRecognizedObjectObservation`" issue, verify the exported model metadata has
`MLModelClassLabels` and a `coremltools` NMS layer with
`coordinatesOutputFeatureName` / `confidenceOutputFeatureName` set; the modern
(>=8.3) exporter does this automatically.

### A.3 AVFoundation real-time pipeline best practices

For a dual-model, 15-30 FPS camera pipeline:

- **Pixel format.** Prefer **`kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`
  (NV12)** over BGRA (Apple Technote TN3121). NV12 is the native sensor format;
  BGRA forces a conversion. `VNImageRequestHandler(cvPixelBuffer:)` accepts NV12
  directly and converts internally on the ANE/GPU path.
- **Capture session.** `.sessionPreset = .hd1280x720` is usually enough for
  navigation-grade depth; 1080p just inflates the pixel-buffer copy without
  improving depth quality at 518^2 input.
- **Drop frames you can't service:** `videoOutput.alwaysDiscardsLateVideoFrames = true`.
- **Queue management.** Use a *single* serial `DispatchQueue` (QoS
  `.userInteractive`) for capture callbacks; inference on that queue or hop once
  to a dedicated inference queue. Avoid `.concurrent` — Core ML on ANE serialises
  execution anyway.
- **Reuse `VNCoreMLRequest` / `VNCoreMLModel` across frames** — re-instantiating
  the model costs ~50-200 ms.
- **Two models per frame.** Start serial (depth then detection on the same
  buffer; ~30 ms + 5 ms ≈ 35 ms ⇒ 28 FPS). A parallel
  `VNImageRequestHandler.perform([req1, req2])` pipeline gains little because
  both target the ANE; don't add the complexity until measured.
- **`MLModelConfiguration.computeUnits = .cpuAndNeuralEngine`** (not `.all`).
  `.all` can spill to GPU under thermal pressure — slower for both these networks
  and competes with the camera preview render. Pinning to ANE keeps latency
  predictable.

### A.4 Sustained inference / thermal behaviour

- **iPhone 17 Pro / Pro Max (vapor chamber, A19 Pro):** effectively no throttling
  on stress tests, ~40 % better sustained perf than iPhone 16 Pro. Excellent
  Roana target.
- **iPhone 17 (base, A19, no vapor chamber):** GSMArena reports a gradual but
  real throttle under sustained load. Acceptable with thermal-aware FPS
  step-down.
- **iPhone 17 Air (A19 Pro, 5-core GPU, "Copper Post" passive design, no vapor
  chamber):** the user's test device and the *hardest* case. Thinner chassis =
  less thermal mass; reaches uncomfortable temps faster than the Pro under
  sustained load, though A19 Pro efficiency (TSMC N3P) and the Copper Post
  heat-spreader help.

```swift
NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, ...) { _ in
    switch ProcessInfo.processInfo.thermalState {
    case .nominal, .fair:     targetFPS = 30  // run full pipeline
    case .serious:            targetFPS = 15  // skip every other frame
    case .critical:           targetFPS = 10  // skip 2/3, drop preview filters
    @unknown default:         targetFPS = 15
    }
}
```

Validate with a 30-min walk test outdoors at ~25 °C with the device in a
holster; expect to enter `.serious` somewhere between 10 and 20 min on the Air
without external airflow.

### A.5 iOS continuous camera / background constraints

- **Foreground only.** Background AVCapture is not permitted for general apps;
  the session must stop on `applicationDidEnterBackground`.
- **Keep screen on:** `UIApplication.shared.isIdleTimerDisabled = true`
  (re-assert on view appearance).
- **Entitlements:** `NSCameraUsageDescription` mandatory; declare accessibility
  use in the App Store description.
- **iOS 18/19 (2025-2026) notes:** the new Swift-only Vision API
  (`ImageRequestHandler` and typed requests) is preferred but the classic
  bridged `VNImageRequestHandler` / `VNCoreMLRequest` still works. Core ML
  `MLComputePolicy` (iOS 17.4+) gives finer ANE-vs-GPU control. On iPhone 15+
  explicitly set 8-bit format and `.activeColorSpace = .sRGB` on the video
  output to avoid extra wide-gamut conversion.

---

## PART B — Android Acceleration Libraries (Layered Strategy)

### B.0 Current Android root-cause track: QNN transport before fallback tuning

The current Snapdragon 8 Gen 2 test device is **not** merely slow. It reports
QNN HTP capability, then fails before either model can be evaluated on HTP:

- Device: Xiaomi `2211133C`, `SM8550`, board `kalama`, Android 16 / HyperOS
  `OS3.0.307.0.WMCCNXM`.
- Artifacts:
  - `logs/v0a-device-20260529T135914Z.log`: V0a loop works, but YOLO falls back
    to CPU/XNNPACK and averages about 1.65 s per inference.
  - `logs/v0a-device-20260529T140409Z.log`: V0b live corridor loses frames
    after both YOLO and Depth Anything fall back to CPU.
  - `logs/qnn-smoke-full-20260529T154349Z.log`: native QNN DSP transport logs
    include `loadRemoteSymbols failed with err 4000`,
    `Failed to create transport for device`, `Failed to load skel`, and
    `Transport layer setup failed: 14001`.
  - `logs/qnn-smoke-20260529T155527Z.log`: the strict gate now classifies this
    as `QNN DSP transport/skeleton setup failed before model-specific offload:
    yolo depth`.

Immediate experiments, in order:

1. **Package/layout audit of installed QNN artifacts.** Confirm the APK and
   installed app contain the expected QNN delegate, QAIRT libraries, HTP stub,
   and skel files for the device ABI, and that Android can load them from their
   runtime location.
2. **QNN delegate option spike.** Exercise any exposed options around unsigned
   process domain, performance control, target backend/architecture, library
   path, and skel path. The goal is to make transport creation succeed, not to
   tune FPS.
3. **LiteRT Next `CompiledModel` spike.** Use the same `.tflite` model through
   the newer LiteRT Qualcomm accelerator to determine whether Google Play AI
   Pack / PODAI distribution avoids the current skel/stub failure mode.
4. **Qualcomm AI Hub context-binary spike.** Try a precompiled AI Hub path for
   the exact Snapdragon tier if LiteRT Next still exposes transport setup
   issues, because it removes on-device compilation variables.
5. **ONNX Runtime QNN cross-check.** Use ORT QNN as a diagnostic only. If ORT
   fails with equivalent transport/skel errors, the root cause is below model
   export and likely in device runtime, packaging, or unsigned-PD setup. If ORT
   transport succeeds while TFLite QNN fails, compare delegate packaging and
   option defaults.

Decision rule:

- If transport fails across runtimes, keep focus on QAIRT/QNN packaging,
  device/runtime version compatibility, signing/unsigned-PD, and delegate setup.
- If transport succeeds but one model fails, then investigate ops, tensor
  formats, quantization, static shapes, and model conversion.
- Do **not** add a lower-performance CPU fallback profile as the fix for this
  target-class phone until the QNN transport/skeleton root cause is known.

### B.1 The 2024-2026 reshuffle in one paragraph

NNAPI was deprecated in Android 15 (2024); Google's migration guide says they
"expect the majority of devices in the future to use the CPU backend" for NNAPI
and recommends LiteRT. Throughout 2025, Google replaced the per-vendor TFLite
delegates with a unified **LiteRT Next** stack centred on a `CompiledModel` API
plus AI Pack distribution via Google Play. The two production NPU integrations
shipped in **Nov 2025 (Qualcomm QNN)** and **Dec 2025 (MediaTek NeuroPilot)**.
Samsung Neural SDK closed to third-party developers, and Xiaomi's MACE has been
dormant since early 2022. ExecuTorch reached v1.0 with
Apple/Qualcomm/MediaTek/Samsung backends. The cleanest 2026 strategy is
therefore **LiteRT Next as the portable layer + Qualcomm AI Hub context binaries
on Snapdragon flagships**.

### B.2 General-purpose / portable layers

#### B.2.1 Google LiteRT Next (recommended portable layer)

- **What it is:** the successor to TensorFlow Lite, with a new C++/Kotlin
  `CompiledModel` API that abstracts CPU / GPU / NPU behind one call:
  `CompiledModel::Create(env, "model.tflite", HwAccelerator::kNpu)`. A
  `TensorBuffer` API enables zero-copy from OpenGL/OpenCL/`AHardwareBuffer` to
  NPU input — important for a camera pipeline.
- **NPU coverage (late 2025 / early 2026):**
  - **Qualcomm QNN Accelerator** — announced 2025-11-24, replaces the old TFLite
    QNN delegate, 90 LiteRT ops, full delegation on 64 of 72 canonical models on
    8 Elite Gen 5, AOT + on-device compilation, dynamic feature modules for
    Hexagon v69/v73/v75/v79/v81.
  - **MediaTek NeuroPilot Accelerator** — announced 2025-12-08, ground-up
    rewrite, targets Dimensity 7300 / 8300 / 9000 / 9200 / 9300 / 9400.
  - **Google Tensor (Pixel):** "Google Tensor SDK is in experimental access"
    per the LiteRT NPU docs; Pixel 10's Tensor G5 has no public NPU plugin yet.
    LiteRT on Pixel currently runs CPU/GPU only for third parties.
- **Third-party app access:** **Yes.** Shipped via the standard Maven AAR
  `com.google.ai.edge.litert:litert` and Google Play "AI Packs" (PODAI), which
  delivers per-SoC compiled binaries automatically — no partner agreement
  needed. This is the key difference from Samsung/MediaTek's prior SDK gates.
- **Update cadence:** multiple production-stack updates through 2025; repo
  `google-ai-edge/LiteRT`. Active.
- **Maturity caveat:** parts of the repo were still labelled alpha in mid-2025.
  **Pin a specific LiteRT version** and re-verify on each release.
- **Expected Depth Anything V2-Small via LiteRT Next QNN on 8 Elite Gen 5:**
  ≈ **31-35 ms** (matches Qualcomm AI Hub's 31.521 ms, since the LiteRT QNN
  Accelerator is the productionised version of the same path). YOLO11n ≈
  **0.7-2 ms**. Total dual-model frame budget ≈ **35 ms ⇒ ~28 FPS**.

#### B.2.2 ONNX Runtime + QNN Execution Provider

- **AAR:** `com.microsoft.onnxruntime:onnxruntime-android-qnn` (1.24.x late
  2025), Maven Central.
- **Coverage:** Qualcomm only (Hexagon HTP + Adreno GPU as of the May 2025
  GPU-backend preview). No MediaTek/Samsung/Tensor EP. The NNAPI EP inherits
  Android 15's deprecation.
- **Verdict:** not the primary Roana runtime, because the current app and model
  assets are already TFLite/LiteRT. Keep ORT QNN as a **diagnostic cross-check**
  while the SM8550 QNN transport issue is unresolved: if ORT fails with the same
  DSP transport/skel errors, the problem is below the TFLite delegate; if ORT
  succeeds, compare runtime packaging and QNN option defaults.

#### B.2.3 Other cross-vendor runtimes

- **MNN (Alibaba), ncnn (Tencent):** mature CPU/GPU (Vulkan), but neither has a
  first-class Snapdragon HTP / Dimensity NPU path beating LiteRT Next in 2026.
  CPU/GPU fallback only.
- **TVM:** research-grade for mobile NPUs; not for production here.
- **ExecuTorch (PyTorch, Meta):** the dark-horse contender. v1.0 (Oct 2025) out
  of beta with Apple Core ML, Qualcomm QNN, MediaTek NeuroPilot, Samsung Exynos
  (new, 60 ops), Vulkan, XNNPACK backends — the closest thing to "one runtime,
  all silicon". Not Roana's primary recommendation only because of migration
  cost from the existing `.tflite`. Re-evaluate 2026 H2.

### B.3 Vendor-specific fast paths

#### B.3.1 Qualcomm — the strongest fast path

1. **LiteRT QNN Accelerator (default).** See B.2.1.
2. **Qualcomm AI Hub pre-compiled context binaries.** For Depth Anything
   V2-Small (`qualcomm/Depth-Anything-V2`):

   | SoC | TFLITE NPU (float) | QNN_DLC NPU (float) | ONNX NPU (float) |
   |---|---|---|---|
   | Snapdragon 8 Gen 3 | **50.806 ms** | 54.928 ms | 54.907 ms |
   | Snapdragon 8 Elite (for Galaxy) | **35.628 ms** | 40.517 ms | 41.513 ms |
   | Snapdragon 8 Elite Gen 5 | **31.521 ms** | 36.034 ms | 34.633 ms |

   For YOLO11n (`qualcomm/YOLOv11-Detection`, 640x640):

   | SoC | TFLITE w8a8 NPU | QNN_DLC w8a16 NPU | QNN_DLC float NPU |
   |---|---|---|---|
   | Snapdragon 8 Gen 3 | **1.105 ms** | 2.98 ms | 2.891 ms |
   | Snapdragon 8 Elite (for Galaxy) | **0.831 ms** | 1.938 ms | 2.249 ms |
   | Snapdragon 8 Elite Gen 5 | **0.728 ms** | 1.768 ms | 1.869 ms |

   On 8 Elite Gen 5, dual-model per-frame compute is **~32 ms ⇒ ~31 FPS**; on
   8 Gen 3, ~52 ms ⇒ ~19 FPS. Both above the 10 FPS floor.
3. **Qualcomm Genie** — GenAI/LLM SDK; not relevant for Roana's CV models. Skip.

#### B.3.2 MediaTek

- **NeuroPilot SDK:** still gated behind a public/basic/partner application
  process; the `ncc-tflite` compiler and Neuron stack require registration.
- **LiteRT NeuroPilot Accelerator:** the Dec 2025 Google-MediaTek announcement
  removes this friction for third-party apps. Use LiteRT Next; don't consume
  NeuroPilot directly.
- **Coverage:** Dimensity 7300 / 8300 / 9000 / 9200 / 9300 / 9400.
- **Depth Anything V2 / YOLO11 numbers on Dimensity:** **not publicly
  published.** MediaTek publishes LLM throughput but not Depth Anything V2-Small.
  Expect 8 Gen 3-class performance for D9300/9400 (~40-60 ms) by TOPS parity;
  confirm on-device.

#### B.3.3 Xiaomi — what was remembered, and what it actually is

The cross-platform Xiaomi library in question was **MACE (Mobile AI Compute
Engine, `XiaoMi/mace`)** — a 2018-era Apache-2.0 inference framework with
NEON / OpenCL / Hexagon DSP support and model conversion from
TF/Caffe/ONNX/PyTorch.

**Status in 2026: effectively abandoned.** Last GitHub release v1.1.1 was
2022-01-13, with master commits trailing off in early 2022. **Do not use MACE.**

There is no current Xiaomi-provided general-purpose third-party acceleration
library. **Xiaomi HyperAI** (HyperOS 2, 2025) is a *features* layer (AI Writing,
AI Erase, AI Interpreter, MiMo LLMs, Gemini partnership) on top of the
Snapdragon/Dimensity NPU — **not** a developer SDK for third-party NPU access.
On Xiaomi 17 Pro Max (Snapdragon 8 Elite Gen 5), Roana should use the standard
LiteRT Next QNN Accelerator.

#### B.3.4 Samsung

- **Samsung Neural SDK:** "no longer provided to third-party developers" per the
  developer-site banner. Closed.
- **ENN Delegate:** `Samsung/ENNDelegate` on GitHub publishes the Exynos Neural
  Network delegate for TFLite — third-party-accessible but Exynos-only and
  lightly documented.
- **ExecuTorch Samsung Exynos backend:** new in ExecuTorch v1.0 (60 operators) —
  the most viable Samsung NPU path for a third-party app in 2026, but only if
  you adopt ExecuTorch.
- **Practical recommendation:** on Galaxy S24/S25 (Snapdragon "for Galaxy"
  globally) the Snapdragon QNN path applies; on Exynos SKUs and Tensor Pixels,
  fall back to LiteRT GPU delegate.

### B.4 Side-by-side: dual-model frame budget

(Depth Anything V2-Small + YOLO11n, NPU/ANE float/FP16 unless noted)

| Platform / Path | Depth (ms) | YOLO11n (ms) | Total (ms) | FPS | Source quality |
|---|---|---|---|---|---|
| iPhone 12 Pro Max / Core ML / ANE | 31.1 | <=5 (est) | ~36 | ~28 | Apple measured + est |
| iPhone 15 Pro Max / Core ML / ANE | 33.9 | <=5 (est) | ~39 | ~26 | Apple measured + est |
| iPhone 17 Air (A19 Pro) / Core ML / ANE | ~25-30 (est) | ~3-5 (est) | ~30-35 | ~28-33 | Extrapolated |
| Snapdragon 8 Gen 3 / LiteRT QNN | 50.8 | 1.1 (w8a8) | ~52 | ~19 | Qualcomm AI Hub measured |
| Snapdragon 8 Elite (Galaxy) / LiteRT QNN | 35.6 | 0.83 | ~36 | ~28 | Qualcomm AI Hub measured |
| Snapdragon 8 Elite Gen 5 / LiteRT QNN | 31.5 | 0.73 | ~32 | ~31 | Qualcomm AI Hub measured |
| Dimensity 9300/9400 / LiteRT NeuroPilot | ~40-60 (est) | ~1-3 (est) | ~45-65 | ~15-22 | Estimated (no public DA-V2 benchmark) |
| Pixel 10 (Tensor G5) / LiteRT GPU only | ~120-200 (est) | ~15 (est) | ~150-215 | ~5-7 | Estimated, no public TPU plugin |

---

## Recommendations

### Layered strategy for Android

**Tier 1 — Portable fallback: LiteRT Next + LiteRT Qualcomm/MediaTek Accelerators.**

- Adopt `com.google.ai.edge.litert:litert` with the **CompiledModel API** as the
  default inference entry point.
- Ship Depth Anything V2-Small as a **single `.tflite`**, AOT-compiled via the
  LiteRT Python AOT API to Qualcomm (SM8550 / SM8650 / SM8750 / SM8850) and
  MediaTek (D9300 / D9400) into a **Google Play AI Pack (PODAI)** — Play delivers
  the right binary per device.
- Runtime fallback chain: `kNpu` → `kGpu` → `kCpu` with an NPU compatibility
  check (`BuiltinNpuAcceleratorProvider`).
- Covers all Snapdragon 8 Gen 1+, all Dimensity 7300+/8300+/9000+, and all
  Adreno/Mali GPU phones as fallback. Effort: ~1-2 engineer-weeks vs the existing
  QNN delegate code.

**Tier 2 — Flagship fast path: Qualcomm AI Hub context binaries on Snapdragon
8 Elite / 8 Elite Gen 5.**

- For premium users on flagship Snapdragon (detect via `Build.SOC_MODEL`),
  bundle the **AI Hub pre-compiled context binary** for `qualcomm/Depth-Anything-V2`
  and `qualcomm/YOLOv11-Detection`.
- Shaves first-frame compile time and squeezes ~2-5 % steady-state perf vs
  on-device compile. Effort: ~1 engineer-week per SoC family.

**Tier 3 (defer): MediaTek-specific tuning, Samsung ENN.**

- Don't ship custom MediaTek/Samsung NPU paths in v1. LiteRT NeuroPilot
  Accelerator handles MediaTek; for Exynos accept GPU-tier perf until
  ExecuTorch's Samsung backend matures (revisit 2026 H2).
- **Pixel users get GPU-only performance** until Google publishes a Tensor TPU
  LiteRT plugin. Communicate this honestly in release notes.

**Thresholds that would change the recommendation:**

- If LiteRT Next QNN on 8 Gen 3 measures >65 ms for Depth Anything V2-Small,
  route those devices to GPU delegate.
- If LiteRT NeuroPilot on Dimensity 9400 measures >80 ms, fall back to GPU
  delegate on MediaTek.
- If ExecuTorch 1.x ships an Exynos backend beating GPU and a Tensor backend
  matching QNN, plan migration in 2026 H2.

### iOS recommendation (engineering cost comparison)

**Ship Core ML directly. No layering needed.**

- Use **Apple's `apple/coreml-depth-anything-v2-small` F16 mlpackage** unchanged.
  Use **Ultralytics `yolo export format=coreml nms=True imgsz=640`** for YOLO11n.
- `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine` (not `.all`).
- AVCaptureVideoDataOutput in **NV12**, `alwaysDiscardsLateVideoFrames = true`,
  serial `.userInteractive` queue, `VNCoreMLRequest` reused across frames.
- Thermal-state-aware FPS step-down (30 → 15 → 10) on `ProcessInfo.thermalState`.
- `isIdleTimerDisabled = true` on the active view.

**Engineering cost vs Android:** Core ML on iOS is roughly **3-5x less code**
than a fully-layered Android NPU strategy: one runtime, one accelerator, one
model package, no PODAI bundling, no per-SoC pre-compilation. The catch is the
platform: Apple closes the device-fragmentation problem at the price of locking
you to Apple Silicon.

### Pre-launch validation benchmarks

| Device class | Min target | Stretch target |
|---|---|---|
| iPhone 17 Air (A19 Pro, no vapor chamber) | Sustained 20 FPS for 20 min at 25 °C | 30 FPS sustained |
| iPhone 15 (A16) — oldest supported | Sustained 15 FPS | 25 FPS |
| Snapdragon 8 Elite Gen 5 (Xiaomi 17 Pro Max, S26 Ultra) | Sustained 25 FPS | 30 FPS |
| Snapdragon 8 Gen 3 (Pixel-class, S24 baseline) | Sustained 15 FPS | 20 FPS |
| Dimensity 9400 (representative device) | Sustained 15 FPS via LiteRT | 20 FPS |
| Pixel 10 (Tensor G5) — GPU fallback | Sustained 10 FPS (hard floor) | 15 FPS |

If any device class fails its minimum, the layered strategy should drop input
resolution from 518^2 to 392^2 for Depth Anything V2-Small (Apple's package
already does this) — ~2x compute reduction with almost no loss in usable depth
quality for navigation.

---

## Caveats

1. **iPhone 17 / A19 Depth Anything V2 latency is extrapolated, not measured.**
   Apple's published benchmarks stop at iPhone 15 Pro Max. The 25-30 ms estimate
   on A19 Pro is derived from Argmax's iPhone 17 NE benchmarks. Verify on the
   iPhone 17 Air dev unit before locking the FPS target.
2. **iPhone 17 Air thermal behaviour under sustained dual-model load is
   unproven.** All public thermal coverage is short-form benchmark/game footage.
   Roana's 20-30 min always-on profile is unlike any benchmarked workload. Run a
   real 30-min walking test before publishing FPS guarantees.
3. **LiteRT Next is fast-moving.** Qualcomm accelerator shipped 2025-11-24,
   MediaTek 2025-12-08; the repo is still partly labelled alpha despite Google's
   production framing. **Pin a specific LiteRT version**; don't take a floating
   `+` dependency.
4. **MediaTek Dimensity 9300/9400 Depth Anything V2 numbers are estimated.** No
   public A/B benchmark exists for this exact model on LiteRT NeuroPilot.
5. **Google Tensor (Pixel) is the weak spot.** No public LiteRT NPU plugin for
   Tensor G2-G5 as of late 2025 ("experimental access"). Pixel users run on
   GPU/CPU with materially worse FPS. Add a Tensor accelerator to Tier 1 if
   Google ships one in 2026.
6. **YOLO11n Core ML NMS export occasionally returns
   `VNCoreMLFeatureValueObservation` rather than `VNRecognizedObjectObservation`**
   (Ultralytics #13794, #14668, #16927). Verify on a sample image after every
   export.
7. **The existing TFLite/LiteRT 2.17 + QNN HTP delegate code does not need to be
   ripped out.** The old delegate still works; the LiteRT Next QNN Accelerator
   is a new path that replaces it without breaking it. Migrate one model at a
   time, starting with Depth Anything V2-Small.
8. **Xiaomi MACE could in principle be forked and revived**, but four years of
   inactivity, no DPT/DINOv2 attention-op support, and no 8 Elite Gen 5 device
   support make this more effort than adopting LiteRT Next. Recommend against.
9. **The current SM8550 QNN failure is a transport failure, not yet a model
   rejection.** Keep using `scripts/verify-qnn-smoke-device.sh` as the gate.
   The first success criterion is native DSP transport/skel setup for any model;
   only then should Roana spend time on model-op compatibility or fallback FPS
   tuning.
