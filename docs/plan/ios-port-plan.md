# iOS Port Plan

> Project decision and staged plan for bringing Roana to iOS as a **first-class
> product platform**, not a cheap cross-platform afterthought. This document
> supersedes the "iOS handling" note in
> [research/02-tech-stack.md](../research/02-tech-stack.md), which deferred iOS
> to a later KMP-or-separate-project decision. The on-device acceleration
> numbers and the cross-platform NPU landscape behind this plan are documented
> in [research/06-acceleration-strategy.md](../research/06-acceleration-strategy.md).

**Status:** accepted for implementation / updated 2026-05-30. Skeleton-first;
wait for the real iPhone before model-performance claims.

---

## 1. Why iOS, why now

The original Android-first decision (research/02) rested on one load-bearing
argument: Depth Anything V2-Small is the pipeline bottleneck, it needs an NPU,
and NPU access on Android is fragmented (QNN for Snapdragon, NeuroPilot for
MediaTek, NNAPI deprecated in Android 15). The entire `InferenceBackend.kt`
capability-probe-and-fall-back dance exists to fight that fragmentation.

On iOS that argument **inverts in our favour**:

1. **The bottleneck model is pre-solved and Apple-blessed.** Apple officially
   publishes a Core ML build of Depth Anything V2-Small
   (`apple/coreml-depth-anything-v2-small`, optimized by the Hugging Face team,
   with sample Swift code in `huggingface/coreml-examples`). Measured Neural
   Engine latency: **31.1 ms on iPhone 12 Pro Max, 33.9 ms on iPhone 15 Pro
   Max** (F16, dominant compute unit = Neural Engine). For comparison, our own
   research/01 target numbers are ~50 ms on Snapdragon 8 Gen 3 and ~36 ms on 8
   Elite. A four-year-old iPhone already beats our target Android SoC on the
   single hardest model.

2. **One NPU, one API, zero fragmentation.** Every iPhone has the Apple Neural
   Engine behind a single stable Core ML / Vision API. No per-vendor delegate
   probing, no silent CPU fallback to defend against.

3. **The accessibility user base skews heavily to iPhone.** For an electronic
   travel aid, iOS is plausibly the *primary* market, not a secondary one
   (VoiceOver has been the de-facto standard for blind users for years). This is
   the product reason; #1 and #2 are why it is also cheap to do well.

This is the same portability move as the V3 glasses step in research/01 §3:
swap the platform layer, reuse the decision core.

---

## 2. Route decision: native Swift + Core ML

**Decision: a separate native Swift/SwiftUI app using AVFoundation + Vision /
Core ML + Core Bluetooth + AVSpeechSynthesizer. Not KMP, not Flutter/RN.**

Rationale:

- **Core ML, not TFLite-on-iOS.** TFLite (LiteRT) does run on iOS with a Core ML
  delegate, which would reuse the existing `.tflite` assets. But the Core ML
  delegate only offloads a *subset* of ops to the ANE and silently falls back
  the rest to CPU; for a DPT/transformer depth model — exactly our bottleneck —
  ANE coverage is materially worse than Apple's hand-converted `.mlpackage`.
  Native Core ML gives strictly better NPU utilization on the model that matters
  most.
- **Not KMP.** The genuinely shared logic is only ~800 LOC of grid math and a
  state machine (see §3). The Core ML depth output layout differs from TFLite
  anyway, so `DepthAnythingTensor` needs an adapter regardless. Introducing the
  KMP iOS-interop toolchain for that little code is net negative for a solo,
  heavily-AI-assisted workflow. A clean Swift port is more idiomatic and more
  AI-friendly to generate.
- **Not Flutter/RN.** Already rejected in research/02 for the same NPU reason;
  on iOS they would force a Core ML bridge anyway.

Anti-divergence between the two codebases is handled by golden test vectors, not
a shared binary — see §5.

---

## 3. What ports, what gets rewritten, what evaporates

Coupling measured against the current ~2300 LOC Kotlin tree:

| Layer | Android files | iOS disposition |
|---|---|---|
| **Decision core (portable, ~800 LOC)** | `CorridorPlanner` (249), `CorridorStateMachine` (78), `CorridorGridFusion` (50), `CorridorPipeline` (57), `FeedbackDispatcher` decision part (81), `DepthAnythingTensor` post-proc (121), `DepthFramePreprocessor` (159) | **Port to Swift**, behaviour-locked by golden vectors |
| **Inference** | `InferenceBackend` (127), `DepthAnythingRunner` (136), `YoloObstacleDetector` decode (305) | **Rewrite, but much smaller.** Vision/Core ML absorb NPU routing + NMS + preprocessing that we hand-rolled on Android |
| **Camera** | `CameraFrameConverter` (277) | **Rewrite as AVFoundation capture.** `AVCaptureVideoDataOutput` yields a `CVPixelBuffer` that Vision consumes directly; no manual YUV→RGB→ByteBuffer dance, but lifecycle, permission, preview, orientation, and frame-cadence diagnostics are real iOS work |
| **App / lifecycle / output** | `MainActivity` (574): camera lifecycle, TTS, (future) BLE, UI | **Rewrite** in SwiftUI + AVSpeechSynthesizer (+ Core Bluetooth later) |

Encouraging consequence: the iOS platform layer is expected to be **smaller**
than the Android one, because Apple's frameworks do work we currently do by
hand. The hand-written QNN juggling, the manual frame conversion, and the raw
YOLO multi-scale decode are the three biggest Kotlin files, and all three shrink
or disappear on iOS.

---

## 4. Model strategy

| Model | Source | Notes |
|---|---|---|
| **Depth Anything V2-Small** | `apple/coreml-depth-anything-v2-small` (F16 `.mlpackage`) | Use as-is on ANE. Write an adapter from its depth-map output to the same planner-grid representation `DepthAnythingTensor.outputToPlannerGrid` produces today. The adapter is the main iOS-specific glue. |
| **YOLO11n detection** | Ultralytics `yolo export format=coreml nms=True` | Export with NMS baked in, drive via `VNCoreMLRequest`, consume `VNRecognizedObjectObservation`. This removes the need to port the raw multi-scale decode in `YoloObstacleDetector`. Preserve only the detections → obstacle-grid mapping that corridor fusion consumes. |

To verify during V0a (do not assume): the exact input/output tensor shapes of
the Apple depth `.mlpackage`, and that the Ultralytics CoreML NMS export plays
cleanly with `VNRecognizedObjectObservation`.

---

## 5. Implementation order

The first iOS slice is **not** the full Android V0a equivalent. It is a smaller
skeleton gate that proves Xcode, signing, camera permission, preview, and frame
callback cadence before any model work. After that, the iOS slices reuse the
same acceptance gates as [v0-implementation-plan.md](v0-implementation-plan.md)
so we are comparing like for like across platforms.

### iOS-S0: skeleton and camera callback gate

Build a native Swift/SwiftUI app in this monorepo under `ios/`.

Suggested layout:

```text
ios/
  Roana/
    Roana.xcodeproj
    Roana/
      RoanaApp.swift
      ContentView.swift
      Camera/
      Diagnostics/
      Info.plist
```

Implementation:

1. Verify host readiness:
   - `xcode-select -p`;
   - `xcodebuild -version`;
   - iPhone visible in Finder / Xcode Devices / `xcrun devicectl list devices`
     when available.
2. Create the smallest SwiftUI app target:
   - app entry point;
   - one camera screen;
   - `NSCameraUsageDescription`;
   - diagnostics for device model, iOS version, launch time, thermal state, and
     camera authorization state.
3. Implement `AVCaptureSession`:
   - back wide-angle camera input;
   - `AVCaptureVideoPreviewLayer` or SwiftUI-compatible preview wrapper;
   - `AVCaptureVideoDataOutput`;
   - prefer `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`;
   - `alwaysDiscardsLateVideoFrames = true`;
   - dedicated serial capture queue.
4. Add frame callback diagnostics:
   - frame dimensions;
   - pixel format;
   - callback interval;
   - rolling p50/p95 callback interval;
   - dropped-frame count if available;
   - queue backlog indicator;
   - thermal state;
   - foreground/background transitions.

Use a stable log prefix:

```text
roana_ios_frame_stats width=... height=... interval_ms=... p50_ms=... p95_ms=... dropped=... thermal=...
```

Acceptance:

- Xcode project opens and builds.
- App signs, installs, and launches on a physical iPhone.
- Permission prompt appears on first launch.
- Denied permission produces a clear non-crashing app state.
- Granted permission starts preview.
- Preview orientation matches the physical device orientation used for testing.
- A 60-second physical-device run produces repeated `roana_ios_frame_stats`.
- No backlog accumulates before model inference exists.
- Entering background stops camera work; returning foreground restarts cleanly.
- `UIApplication.isIdleTimerDisabled = true` while the camera view is active.

Acceptance artifact:

```text
logs/ios-skeleton-<timestamp>.log
```

The first iOS commit should prove build + on-device camera preview, no models
yet. Suggested branch/PR per repo convention:
`feat(ios): bootstrap SwiftUI skeleton with AVCaptureSession preview`.

### iOS-V0a: minimum closed loop

Start only after iOS-S0 passes.

1. Load YOLO11n Core ML.
2. Run one detection via `VNCoreMLRequest`.
3. Turn one detection event into `AVSpeechSynthesizer` speech.
4. Log frame timing, inference timing, dropped frames, and speech events.

Acceptance: runs on a real iPhone; analysis does not backlog; a detected
obstacle triggers spoken output. (Same gate as Android V0a.)

### iOS-V0b: corridor demo

1. Add the Apple Depth Anything V2-Small `.mlpackage` on the ANE.
2. Write the depth-output → planner-grid adapter.
3. Port `CorridorGridFusion` → DFS `CorridorPlanner` → conservative
   `CorridorStateMachine` to Swift, locked by golden vectors (§6).
4. Emergency override for near obstacle, frame loss, low confidence.
5. Known-corridor blindfold test with a sighted spotter.

Acceptance: end-to-end ≥10 FPS, no frame backlog, prefers `STOP` on uncertainty,
no 30-minute thermal throttle (monitor `ProcessInfo.thermalState`). (Same gates
as Android V0b; depth is expected to be ~30 ms on ANE, well inside budget.)

### Behavioural parity mechanism (the anti-divergence seam)

The portable modules already have Kotlin unit tests: `CorridorPlannerTest`,
`CorridorGridFusionTest`, `CorridorPipelineTest`, `FeedbackDispatcherTest`,
`DepthFramePreprocessorTest`. Plan:

1. Add a small Kotlin step that dumps each test's `(input, expected output)` as
   JSON fixtures into a shared `parity/` directory in the repo.
2. The Swift port loads the **same** fixtures and asserts identical output.

This guarantees the two decision cores stay behaviourally identical without a
shared binary, and turns "did the Swift port drift?" into a CI check rather than
a manual worry. It also formalizes the research/01 §6 promise (platform-swappable
core) as an executable contract.

---

## 6. iOS-specific risks and decisions (things genuinely harder than Android)

1. **Continuous camera in background.** iOS will not run the camera with the
   screen off or the app backgrounded the way an Android foreground Service can.
   Decision: run foreground, screen-on, `UIApplication.isIdleTimerDisabled =
   true`. Acceptable for a chest-harness ETA. The orange camera-active indicator
   will show; fine for a privacy-first product.
2. **Core Bluetooth background limits** (affects V1 bone-conduction routing and
   V2 Bangle.js haptics, not the V0-equivalent). CB central background mode is
   more constrained than Android GATT; revisit when BLE comes into scope.
3. **Distribution is not "sideload a debug APK".** Self-test: Xcode direct
   install to a registered device (free account = 7-day provisioning). Testing
   with real blind users beyond yourself needs a **paid Apple Developer account
   ($99/yr) + TestFlight**. Budget this before user testing, not during.
4. **Bone-conduction audio routing** via `AVAudioSession` is arguably cleaner
   than Android — a mild plus, noted for V1.

---

## 7. Safety and privacy gates (carried over, non-negotiable)

All research/01 + v0-plan gates apply unchanged on iOS:

- no video-frame upload; no frame storage by default;
- no face recognition or identity tracking; no cloud VLM call;
- no command that tells the user to cross a street;
- low confidence / missing frames / uncertain geometry must prefer `STOP` over
  `CLEAR`.

The existing `PrivacyBoundaryTest.kt` intent should get a Swift equivalent so
the boundary is enforced on both platforms.

---

## 8. Out of scope for the iOS V0-equivalent

- BLE, bone-conduction routing, Bangle.js 2 haptics (matches Android V0).
- Smart-glasses camera source (V3).
- VLM "what's that?" query flow.
- Custom walkable-area training.
- App Store release (TestFlight self-test only at this stage).
- Outdoor street / crosswalk navigation.

---

## 9. Mode B → Mode A handoff

The skeleton, the route decisions in this doc, the depth-output adapter, and the
golden-vector parity harness are **Mode B** (high rollback cost, founder + local
Claude Code). Once those exist plus an iOS `AGENTS.md` with the hard constraints
above, the per-module grind — porting each pure module to Swift against its
fixtures, wiring each platform API — has a low rollback cost and clear spec, and
can move to **Mode A** cloud routines.

---

## 10. Stop gates

Stop and report after any of these:

1. Xcode/device signing blocks physical install.
2. Camera permission or preview cannot be made reliable.
3. Frame callbacks are unstable before any model work.
4. The 60-second skeleton run passes.
5. YOLO Core ML loads and speaks one detection.
6. Depth Anything loads and produces one planner-grid output.
7. The full iOS V0b corridor demo passes.

Only after stop gate 4 should model loading begin.

## 11. Open questions for founder review

1. iPhone model on hand (sets the real ANE perf ceiling and the minimum support
   target).
2. Paid Apple Developer account now (unblocks TestFlight + blind-user testing) or
   later (self-test only for now)?
