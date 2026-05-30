# iOS Port Active Status

Updated: 2026-05-30.

## Current State

- Active objective: implement `docs/plan/ios-port-plan.md` via `intuitive-flow`.
- Latest user instruction: do code development first because no iPhone is
  currently connected; defer hardware tests until all or most code parts are
  done.
- Current slice: code-first iOS S0/V0a/V0b scaffold while hardware proof is
  deferred.
- Host readiness observed on this machine:
  - `xcode-select -p` returns `/Library/Developer/CommandLineTools`.
  - `xcodebuild -version` fails because full Xcode is not the active developer
    directory.
  - `xcrun simctl` and `xcrun devicectl` are unavailable for the same reason.

## Implemented Code

- Native SwiftUI app scaffold under `ios/Roana`.
- Xcode project shell at `ios/Roana/Roana.xcodeproj`.
- Camera permission declaration in `Info.plist`.
- SwiftUI entry point and camera screen.
- `AVCaptureSession` setup for the back wide-angle camera.
- `AVCaptureVideoPreviewLayer` SwiftUI bridge.
- `AVCaptureVideoDataOutput` using
  `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`.
- `alwaysDiscardsLateVideoFrames = true`.
- Dedicated serial queues for session setup and frame callbacks.
- Device diagnostics for hardware identifier, iOS version, launch uptime,
  thermal state, and camera authorization state.
- Frame diagnostics with dimensions, pixel format, callback interval, rolling
  p50/p95 interval, dropped-frame count, backlog indicator, and thermal state.
- Stable log prefix:
  `roana_ios_frame_stats width=... height=... interval_ms=... p50_ms=... p95_ms=... dropped=... thermal=...`.
- Foreground/background handling stops camera work in background and restarts
  when active.
- `UIApplication.isIdleTimerDisabled = true` while the camera view is active.
- Code-only iOS-V0a path:
  - YOLO11n Core ML loader scaffold using `VNCoreMLRequest`.
  - NMS-export consumption shape via `VNRecognizedObjectObservation`.
  - Missing model state is non-crashing and logs `roana_ios_yolo
    status=model_missing`.
  - Detection timing logs use `roana_ios_yolo`.
  - Detection-to-speech wiring uses `AVSpeechSynthesizer` and logs
    `roana_ios_speech`.
- Code-only iOS-V0b decision-core path:
  - Swift `CorridorPlanner` port with near-obstacle STOP, 15x15 DFS path
    search, safe-cell thresholds, horizontal-clearance tie-break, and
    LEFT/STRAIGHT/RIGHT/STOP commands.
  - Swift `CorridorStateMachine` port with 3-frame confirmation and immediate
    emergency STOP for `frame_loss` / `low_confidence`.
  - Swift `CorridorGridFusion` port that marks high-confidence detections as
    obstacle cells in the planner grid.
  - Swift `CorridorPipeline` wrapper that logs `roana_ios_corridor`.
  - Swift `CorridorFeedbackDispatcher` ports Android's changed-state and
    initial-emergency-STOP speech rules, logs `roana_ios_corridor_feedback`,
    and is wired into the camera corridor pipeline.
- Code-only Depth Anything path:
  - `DepthAnythingOutputAdapter` converts raw depth output values or
    `MLMultiArray` outputs into the 15x15 planner grid.
  - `DepthAnythingRunner` loads a bundled `DepthAnythingV2Small` Core ML
    resource when present, requests all compute units, runs a `VNCoreMLRequest`,
    and logs `roana_ios_depth`.
  - Camera callbacks now attempt depth inference, feed successful depth grids
    plus YOLO detections into `CorridorPipeline`, and leave missing-model depth
    state as a no-op until assets are available. Non-missing depth failures
    route through conservative `low_confidence` STOP.
  - The adapter supports common Core ML depth layouts:
    `[H,W]`, `[H,W,1]`, `[1,H,W]`, `[1,H,W,1]`, and `[1,1,H,W]`.
  - Pure Swift smoke tests cover small-output fallback, optimized large-output
    aggregation, and constant-output normalization.
- Executable local proof:
  - `swiftc ios/Roana/Roana/Corridor/CorridorPlanner.swift ios/Roana/Roana/Corridor/CorridorStateMachine.swift ios/Roana/Roana/Corridor/CorridorGridFusion.swift ios/Roana/Roana/Corridor/CorridorPipeline.swift ios/Roana/RoanaTests/main.swift -o /tmp/roana-corridor-smoke && /tmp/roana-corridor-smoke`
    passes with `CorridorCoreSmoke passed`.
  - Swift parity verifier reads `parity/corridor-core.json` and passes the
    planner, fusion, and state-machine cases mirrored from current Kotlin unit
    tests.
  - Depth adapter smoke verifier passes without an iPhone or full Xcode.
  - `scripts/analyze-ios-log.py` and `scripts/test_analyze_ios_log.py` define
    the future machine-checkable log gates for iOS S0/V0a/V0b artifacts.
- Parity status:
  - Checked-in JSON fixture exists at `parity/corridor-core.json`.
  - Automatic Kotlin fixture generation is still pending because local Gradle
    currently fails before task execution under the installed OpenJDK 25
    environment (`What went wrong: 25.0.1`). Use JDK 17 or 21 before relying on
    Gradle-backed Kotlin generation.

## Local Code Gate

Run:

```bash
scripts/verify-ios-s0-local.sh
```

Expected result on this machine until full Xcode is selected: structural checks
and the portable Swift corridor smoke pass, then the script exits `2` with
build deferred. Latest observed output:

```text
xcodebuild requires full Xcode; iOS local structural checks passed, build deferred
```

Expected result on a full-Xcode host: structural checks pass and
`xcodebuild -project ios/Roana/Roana.xcodeproj -scheme Roana -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
passes.

## Deferred Hardware Proof

The following iOS-S0 acceptance items remain intentionally unproven until an
iPhone and full Xcode are available:

- Xcode project opens and builds in Xcode.
- App signs, installs, and launches on a physical iPhone.
- Permission prompt appears on first launch.
- Denied permission produces a clear non-crashing app state.
- Granted permission starts preview.
- Preview orientation matches the physical device orientation used for testing.
- A 60-second physical-device run produces repeated `roana_ios_frame_stats`.
- No backlog accumulates before model inference exists.
- Entering background stops camera work; returning foreground restarts cleanly.

Acceptance artifact target:

```text
logs/ios-skeleton-<timestamp>.log
```

Machine-check the artifact with:

```bash
scripts/analyze-ios-log.py --log logs/ios-skeleton-<timestamp>.log --require-background-stop 1
```

After model assets are available, add `--require-yolo 1 --require-depth 1
--require-corridor 1 --require-speech 1`.

## No-Touch Scope

- Do not add real iOS Core ML model assets, benchmark claims, or performance
  gates until iOS-S0 builds under full Xcode and runs on a physical iPhone.
- Do not add large Core ML model artifacts directly to git; keep generated
  `.mlmodelc` / `.mlpackage` outputs out of normal source commits unless Git
  LFS or an explicit model-fetch path is added.
- Do not treat the Swift corridor smoke as full anti-divergence proof; the
  JSON fixture now covers the initial corridor core cases, but automatic Kotlin
  fixture generation from source tests is still pending.
- Do not claim iPhone performance, preview orientation, signing, installation,
  or camera callback cadence until physical-device evidence exists.
- Do not resume Android QNN diagnosis while this iOS port slice is active.
