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
- Single-flight model inference coordinator keeps `AVCaptureVideoDataOutput`
  callbacks short, runs model work on `app.roana.ios.inference`, and logs
  `roana_ios_inference status=scheduled|skipped|finished` so slow model frames
  are dropped instead of accumulating queued inference work.
- Foreground/background handling stops camera work in background and restarts
  when active; the physical log verifier now requires ordered background-stop
  then camera-restart evidence for granted-camera S0/V0 artifacts.
- Denied or restricted camera authorization logs `camera_permission_denied` and
  leaves the app in a non-crashing permission-required state; the future denied
  permission artifact can be checked separately from the granted-camera run.
- `UIApplication.isIdleTimerDisabled = true` while the camera view is active.
  Idle-timer state changes emit `roana_ios_lifecycle idle_timer_disabled`
  evidence, and granted-camera physical log gates now require disable/enable
  evidence so the first device run proves the app keeps the camera session
  awake only while active.
- Preview and capture-output orientation configuration now emit stable
  `roana_ios_orientation` / `camera_output_orientation` logs so the first
  physical S0 run has machine-checkable evidence that orientation handling was
  configured. Visual correctness still requires the deferred iPhone run.
- Code-only iOS-V0a path:
  - YOLO11n Core ML loader scaffold using `VNCoreMLRequest`.
  - NMS-export consumption shape via `VNRecognizedObjectObservation`.
  - Missing model state is non-crashing and logs `roana_ios_yolo
    status=model_missing`.
  - Successful model load logs `roana_ios_yolo status=model_description` with
    Core ML input/output feature names, shapes, and metadata so YOLO export
    assumptions can be checked from the first iPhone artifact.
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
  - Successful model load logs `roana_ios_depth status=model_description` with
    Core ML input/output feature names, shapes, and metadata so the Apple
    `.mlpackage` contract can be checked from the first iPhone artifact.
  - Camera callbacks now attempt depth inference, feed successful depth grids
    plus YOLO detections into `CorridorPipeline`, and leave missing-model depth
    state as a no-op until assets are available. Non-missing depth failures
    route through conservative `low_confidence` STOP.
  - The adapter supports common Core ML depth layouts:
    `[H,W]`, `[H,W,1]`, `[1,H,W]`, `[1,H,W,1]`, and `[1,1,H,W]`.
  - Pure Swift smoke tests cover small-output fallback, optimized large-output
    aggregation, and constant-output normalization.
- iOS model asset contract:
  - Manifest exists at `ios/Roana/Roana/ModelAssets/manifest.json`.
  - The app target copies `ModelAssets` as a bundle resource.
  - `ModelAssetResourceLocator` looks for both root-bundled and
    `ModelAssets/`-nested `YOLO11n` and `DepthAnythingV2Small` resources with
    `.mlmodelc` or `.mlpackage` extensions.
  - `scripts/check-ios-model-assets.py` validates the manifest and can enforce
    local asset presence with `--require-present`.
  - `scripts/install-ios-model-assets.py` stages local `.mlpackage` or
    `.mlmodelc` directories into the expected bundle names by copy or symlink.
  - Current local model asset status is intentionally `missing` because large
    Core ML assets are not committed.
- iOS safety/privacy boundary:
  - iOS subtree agent contract exists at `ios/AGENTS.md` and records the
    hard platform, privacy, safety, verification, and out-of-scope constraints
    for future iOS work.
  - Swift verifier exists at `ios/Roana/RoanaTests/Privacy/main.swift`.
  - The verifier enforces the iOS V0 camera-only `Info.plist` boundary and scans
    production Swift source for network, frame-storage, identity, cloud/VLM, and
    street-crossing guidance tokens.
- Executable local proof:
  - `swiftc ios/Roana/Roana/Corridor/CorridorPlanner.swift ios/Roana/Roana/Corridor/CorridorStateMachine.swift ios/Roana/Roana/Corridor/CorridorGridFusion.swift ios/Roana/Roana/Corridor/CorridorPipeline.swift ios/Roana/Roana/Speech/CorridorFeedbackDispatcher.swift ios/Roana/RoanaTests/main.swift -o /tmp/roana-corridor-smoke && /tmp/roana-corridor-smoke`
    passes with `CorridorCoreSmoke passed`.
  - Swift parity verifier reads `parity/corridor-core.json` and passes the
    planner, fusion, depth-grid conversion, state-machine, pipeline, and
    feedback-dispatch cases mirrored from current Kotlin unit tests.
  - Depth adapter smoke verifier passes without an iPhone or full Xcode.
  - iOS model asset checker tests pass; the default checker reports both
    expected resources as missing until real local model assets are supplied.
  - iOS model asset installer tests pass without requiring real model binaries.
  - Swift privacy boundary verifier passes without full Xcode.
  - Frame inference coordinator smoke verifier passes without full Xcode.
  - `scripts/analyze-ios-log.py` and `scripts/test_analyze_ios_log.py` define
    the future machine-checkable log gates for iOS S0/V0a/V0b artifacts,
    including frame stats, orientation evidence, Core ML model-description
    logs, ordered background-stop/restart evidence, idle-timer disable/enable
    evidence, model/corridor/speech evidence, and inference coordinator
    scheduled/skipped/finished counts.
  - `scripts/verify-ios-device-log.py` wraps host/device readiness, optional
    model-asset checks, and the iOS log analyzer for S0/V0a/V0b physical-run
    artifacts. All granted-camera physical-run gates require preview/capture
    orientation evidence, ordered background-stop/restart evidence, and
    idle-timer disable/enable evidence by default. V0a/V0b defaults require
    YOLO model-description evidence, and V0b defaults require Depth Anything
    model-description evidence, so the first model-backed device artifact
    proves the exported Core ML feature contract instead of only proving
    inference callbacks. V0b defaults also require p95 frame cadence at or
    below 100 ms and thermal state no worse than `fair`, matching the
    corridor-demo ≥10 FPS / no-throttle acceptance gate.
  - `scripts/verify-ios-device-log.py --gate s0-denied` checks the denied
    permission artifact without requiring camera start, frame stats, or
    orientation logs.
- Parity status:
  - Checked-in JSON fixture exists at `parity/corridor-core.json`.
  - Kotlin fixture generation source exists at
    `app/src/test/java/com/roana/app/parity/CorridorParityFixtureGenerator.kt`.
  - Gradle task `:app:generateCorridorParityFixtures` is wired to regenerate
    `parity/corridor-core.json`.
  - Running the Gradle task is still pending because this shell's default
    `JAVA_HOME` points at `/opt/homebrew/opt/openjdk/bin/java` instead of a JDK
    home, and with `JAVA_HOME` corrected to the installed OpenJDK 25 home,
    Gradle still fails before task execution with
    `java.lang.IllegalArgumentException: 25.0.1`. Use JDK 17 or 21 before
    relying on Gradle-backed Kotlin generation.

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
scripts/analyze-ios-log.py --log logs/ios-skeleton-<timestamp>.log --require-background-stop 1 --require-background-cycle 1 --require-orientation 1 --require-idle-timer 1
```

Or use the physical-run wrapper:

```bash
scripts/verify-ios-device-log.py --gate s0 --log logs/ios-skeleton-<timestamp>.log
```

For the denied-permission S0 artifact, capture the launch after denying camera
permission and run:

```bash
scripts/verify-ios-device-log.py --gate s0-denied --log logs/ios-permission-denied-<timestamp>.log
```

After model assets are available, add `--require-yolo 1
--require-yolo-description 1 --require-depth 1 --require-depth-description 1
--require-corridor 1 --require-speech 1 --require-inference 1
--max-p95-ms 100 --max-thermal-state fair` when calling the analyzer directly
for V0b. The physical-run wrapper applies the V0a/V0b model-description
requirements and the V0b cadence/thermal requirements by default.

Before running model-backed iOS V0a/V0b gates, check the local asset contract:

```bash
scripts/check-ios-model-assets.py --require-present
```

## No-Touch Scope

- Do not add real iOS Core ML model assets, benchmark claims, or performance
  gates until iOS-S0 builds under full Xcode and runs on a physical iPhone.
- Do not add large Core ML model artifacts directly to git; keep generated
  `.mlmodelc` / `.mlpackage` outputs out of normal source commits unless Git
  LFS or an explicit model-fetch path is added.
- Do not treat the Swift corridor smoke as full anti-divergence proof; the
  JSON fixture now covers planner, fusion, depth-grid conversion, state-machine,
  pipeline, and feedback-dispatch cases, but automatic Kotlin fixture generation
  from source tests is still pending on a JDK 17/21 host.
- Do not claim iPhone performance, preview orientation, signing, installation,
  or camera callback cadence until physical-device evidence exists.
- Do not resume Android QNN diagnosis while this iOS port slice is active.
