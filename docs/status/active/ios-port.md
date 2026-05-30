# iOS Port Active Status

Updated: 2026-05-30.

## Current State

- Active objective: implement `docs/plan/ios-port-plan.md` via `intuitive-flow`.
- Latest user instruction: continue parked iOS V0b work one item at a time via
  `intuitive-flow`, keeping this iOS worktree iOS-only and not pursuing
  Android/JDK verification here.
- Current slice: iOS V0b proof. Code, model assets, and local replay are ready;
  the physical iPhone app install succeeded, but launch/log capture is waiting
  for the device to return from CoreDevice offline/unavailable state.
- Current code-only model execution mode: S0 defaults to
  `roana_ios_model_mode value=disabled` and does not schedule YOLO/depth
  inference. Debug builds opt into V0a YOLO with `--roana-enable-yolo` or
  `ROANA_IOS_MODEL_MODE=yolo`, and opt into V0b corridor/depth with
  `--roana-enable-corridor` or `ROANA_IOS_MODEL_MODE=corridor`.
  Shared Xcode schemes keep those runs explicit: `Roana` is the no-model S0
  scheme, `Roana-V0a-YOLO` enables YOLO only, and `Roana-V0b-Corridor` enables
  corridor mode plus the debug frame-loss proof hook.
- Host readiness observed on this machine:
  - `xcode-select -p` returns `/Applications/Xcode.app/Contents/Developer`.
  - `xcodebuild -version` reports Xcode 26.5.
  - `xcrun devicectl` is available.
  - iPhone `MiaoDX003` (`00008150-000E35310E82401C`,
    CoreDevice `A85B7E8D-1EDD-573F-9C50-BC76B9FB8E03`) is known and paired, but
    latest observed state is `unavailable` / `xctrace` offline after a
    successful app install.

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
  Frame stats also include `run_s` so future S0/V0 artifacts prove run
  duration rather than only frame count.
- Stable log prefix:
  `roana_ios_frame_stats width=... height=... interval_ms=... p50_ms=... p95_ms=... dropped=... thermal=... run_s=...`.
- Single-flight model inference coordinator keeps `AVCaptureVideoDataOutput`
  callbacks short, runs model work on `app.roana.ios.inference`, and logs
  `roana_ios_inference status=scheduled|skipped|finished` so slow model frames
  are dropped instead of accumulating queued inference work.
- Model-backed inference is launch-mode gated for code-first development:
  default S0 camera runs remain a true no-model skeleton, V0a runs enable YOLO
  only, and V0b runs enable YOLO plus Depth Anything/corridor feedback. The
  physical log verifier now checks `roana_ios_model_mode` by gate so artifacts
  prove which path was actually exercised. Frame-loss safety is routed through
  corridor STOP feedback only in corridor mode; S0/V0a still log dropped frames
  without emitting corridor guidance.
- Shared Xcode schemes exist for the three code paths: `Roana` for S0,
  `Roana-V0a-YOLO` for YOLO-only V0a, and `Roana-V0b-Corridor` for
  corridor/depth V0b with `--roana-debug-fail-safe-stop`.
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
  `roana_ios_orientation` / `camera_output_orientation` logs from a shared
  `CameraFrameOrientation` mapping. YOLO and Depth Anything inference use that
  same mapping for `VNImageRequestHandler` and log `vision=...`, so the first
  physical model-backed run has machine-checkable evidence that preview,
  capture output, and model input orientation agree. Visual correctness still
  requires the deferred iPhone run.
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
    `roana_ios_speech` for the YOLO-only V0a path.
  - YOLO-only speech uses a portable `YoloSpeechFeedbackPolicy` so repeated
    detections of the same label are throttled while different obstacle labels
    can still interrupt promptly; a pure Swift smoke test verifies the policy
    without an iPhone.
  - Speech output now activates an `AVAudioSession` with playback /
    spoken-audio / duck-others settings before queuing utterances and logs
    `roana_ios_audio_session`, giving future device artifacts proof that speech
    was prepared for audible output.
  - V0a log analysis now requires queued speech to share a label with an
    observed YOLO detection, so the first model-backed artifact proves a
    detection-to-speech closed loop rather than independent model and speech
    callbacks.
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
  - Corridor feedback uses the same speech audio-session activation path before
    queuing command utterances.
  - When depth/corridor feedback is active, generic YOLO object speech is
    suppressed with `roana_ios_speech status=suppressed` and
    `reason=corridor_feedback_active`; corridor feedback owns spoken guidance
    so V0b does not emit competing "object ahead" and corridor-command
    utterances for the same frame.
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
  - Dropped capture frames and inference-busy skipped frames now emit
    `roana_ios_safety event=fail_safe_stop reason=frame_loss` and route through
    corridor `failSafeStop(reason: "frame_loss")`. `CorridorPipeline` serializes
    state-machine updates with a lock so normal inference and frame-loss safety
    events cannot race each other.
  - Debug builds can force the same frame-loss proof path at launch with
    `--roana-debug-fail-safe-stop` or `ROANA_DEBUG_FAIL_SAFE_STOP=1`; release
    builds leave the hook disabled.
  - The adapter supports common Core ML depth layouts:
    `[H,W]`, `[H,W,1]`, `[1,H,W]`, `[1,H,W,1]`, and `[1,1,H,W]`.
  - Pure Swift smoke tests cover small-output fallback, optimized large-output
    aggregation, and constant-output normalization.
- iOS model asset contract:
  - Manifest exists at `ios/Roana/Roana/ModelAssets/manifest.json`.
  - The manifest records expected model contracts: YOLO11n image input
    `640x640` with Vision object-observation output, and Depth Anything image
    input `518x518` with `MLMultiArray` output.
  - The app target copies `ModelAssets` as a bundle resource.
  - `ModelAssetResourceLocator` looks for both root-bundled and
    `ModelAssets/`-nested `YOLO11n` and `DepthAnythingV2Small` resources with
    `.mlmodelc` or `.mlpackage` extensions.
  - `ios/Roana/RoanaTests/ModelAssets/main.swift` covers the app-side bundle
    lookup path with temporary root and `ModelAssets/`-nested `.mlmodelc` /
    `.mlpackage` fixtures, so the staged names used by the installer are
    checked before a real iPhone run.
  - `scripts/check-ios-model-assets.py` validates manifest schema, expected
    model contracts, and can enforce local asset presence with
    `--require-present`.
  - `scripts/install-ios-model-assets.py` stages local `.mlpackage` or
    `.mlmodelc` directories into the expected bundle names by copy or symlink.
    Symlink mode is preferred for local testing, and copy mode has an explicit
    large-asset guard so model binaries do not get casually duplicated into the
    app tree.
  - Current local model asset status is intentionally `missing` because large
    Core ML assets are not committed.
- iOS safety/privacy boundary:
  - iOS subtree agent contract exists at `ios/AGENTS.md` and records the
    hard platform, privacy, safety, verification, and out-of-scope constraints
    for future iOS work.
  - Swift verifier exists at `ios/Roana/RoanaTests/Privacy/main.swift`.
  - The verifier enforces the iOS V0 camera-only `Info.plist` boundary, scans
    production Swift source for network, frame-storage, forbidden framework,
    identity, cloud/VLM, and street-crossing guidance tokens, and reports the
    exact source file/line for violations.
  - `scripts/test_ios_privacy_boundary.py` compiles the verifier and exercises
    camera-only pass, forbidden source, forbidden framework import, and
    forbidden `Info.plist` negative fixtures.
- Executable local proof:
  - `swiftc ios/Roana/Roana/Corridor/CorridorPlanner.swift ios/Roana/Roana/Corridor/CorridorStateMachine.swift ios/Roana/Roana/Corridor/CorridorGridFusion.swift ios/Roana/Roana/Corridor/CorridorPipeline.swift ios/Roana/Roana/Speech/CorridorFeedbackDispatcher.swift ios/Roana/RoanaTests/main.swift -o /tmp/roana-corridor-smoke && /tmp/roana-corridor-smoke`
    passes with `CorridorCoreSmoke passed`.
  - Swift parity verifier reads `parity/corridor-core.json` and passes the
    planner, fusion, depth-grid conversion, state-machine, pipeline, and
    feedback-dispatch cases mirrored from current Kotlin unit tests.
  - iOS local verification consumes the checked-in parity fixture only; Android
    fixture regeneration and JDK/Gradle checks are not part of the iOS V0b gate.
  - `scripts/check-ios-xcodeproj-membership.py` verifies that every production
    Swift file under `ios/Roana/Roana` is present in the app target's Sources
    build phase and that `Assets.xcassets` / `ModelAssets` are present in the
    Resources phase. The current project reports 24 Swift sources and no
    missing membership.
  - Depth adapter smoke verifier passes without an iPhone or full Xcode.
  - Model asset bundle-locator smoke verifier passes without an iPhone or full
    Xcode.
  - iOS model asset checker tests pass; the default checker reports both
    expected resources as missing until real local model assets are supplied.
  - iOS model asset installer tests pass without requiring real model binaries.
  - Swift privacy boundary verifier and negative-fixture tests pass without
    full Xcode.
  - Frame inference coordinator smoke verifier passes without full Xcode.
  - `scripts/analyze-ios-log.py` and `scripts/test_analyze_ios_log.py` define
    the future machine-checkable log gates for iOS S0/V0a/V0b artifacts,
    including frame stats, orientation evidence, Core ML model-description
    logs, ordered background-stop/restart evidence, idle-timer disable/enable
    evidence, model/corridor/speech evidence, and inference coordinator
    scheduled/skipped/finished counts. V0a speech gates require a queued speech
    label that matches a YOLO detection label. V0a/V0b speech gates require
    audio-session activation evidence, and V0b log gates also require a
    machine-checkable fail-safe STOP artifact for frame-loss safety.
    Model-description gates now check the expected Core ML contracts from the
    manifest: YOLO image input `640x640`, Depth Anything image input `518x518`,
    and multi-array model outputs where applicable.
  - `scripts/verify-ios-device-log.py` wraps host/device readiness, optional
    model-asset checks, and the iOS log analyzer for S0/V0a/V0b physical-run
    artifacts. All granted-camera physical-run gates require preview/capture
    orientation evidence, ordered background-stop/restart evidence, and
    idle-timer disable/enable evidence by default, plus at least 60 seconds of
    `run_s` frame evidence. V0a/V0b defaults require YOLO model-description
    evidence, and V0b defaults require Depth Anything model-description
    evidence, so the first model-backed device artifact proves the exported
    Core ML resource and feature contract instead of only proving inference
    callbacks.
    V0a/V0b defaults require Vision orientation evidence from the model logs.
    V0b defaults also require frame-loss fail-safe STOP evidence, p95 frame
    cadence at or below 100 ms, and thermal state no worse than `fair`,
    matching the corridor-demo ≥10 FPS / no-throttle acceptance gate.
    Gate defaults also require mode evidence: S0 and denied-camera artifacts
    require `disabled`, V0a requires `yolo`, and V0b requires `corridor`.
    Host readiness now parses `devicectl --json-output` and blocks with
    `iphone_device_available` when the iPhone is known but offline/unavailable.
  - `scripts/verify-ios-device-log.py --gate s0-denied` checks the denied
    permission artifact without requiring camera start, frame stats, or
    orientation logs.
  - `scripts/capture-ios-device-log.py` standardizes future physical-run log
    artifacts under `logs/ios-*.log` from stdin, an existing file, or an
    explicit capture command, then immediately runs `verify-ios-device-log.py`
    for the selected S0/V0a/V0b gate.
  - Local model assets are present and `scripts/check-ios-model-assets.py
    --require-present` reports `status=ready` for `YOLO11n.mlmodelc` and
    `DepthAnythingV2Small.mlmodelc`.
  - Local offline replay proof passes against the user-recorded, git-ignored
    `samples/home_iphone_0530.mp4` fixture. The short STOP smoke passes with:
    `scripts/replay-ios-video.sh samples/home_iphone_0530.mp4 --fps 1
    --max-seconds 2 | tee /tmp/roana-ios-video-replay-smoke.log`, followed by
    `scripts/verify-ios-replay-log.py --log
    /tmp/roana-ios-video-replay-smoke.log --fixture stop --min-run-seconds 2
    --max-p95-ms 1000`. The verifier reports `status=passed` with YOLO,
    Depth Anything, Vision orientation, corridor feedback, and STOP evidence.
    The longer guidance probe also passes with `--fps 2 --max-seconds 20` and
    `scripts/verify-ios-replay-log.py --fixture guidance --min-run-seconds 20
    --max-p95-ms 500`, proving at least one normal RIGHT/STRAIGHT guidance
    utterance plus audio-session evidence from the replay harness.
    Replay logs now also include `roana_ios_motion_quality label=stable
    reason=motion_unavailable trusts_guidance=true source=replay`, and replay
    verification requires that evidence so image-only fixtures prove that
    missing motion data does not block guidance.
  - `scripts/label-ios-replay.py` can create a local JSON label summary from an
    existing replay log or by running replay against a local video. It suggests
    command labels (`STOP`, `STRAIGHT`, `LEFT`, `RIGHT`), scene-quality labels
    such as `too_close` / `occluded` / `pointing_down` / `unstable`, and a
    fixture type, and emits approximate segment labels from replay frame
    timestamps, without adding production recording or committing videos.
- Parity status:
  - Checked-in JSON fixture exists at `parity/corridor-core.json`.
  - Kotlin fixture generation source exists at
    `app/src/test/java/com/roana/app/parity/CorridorParityFixtureGenerator.kt`.
  - Gradle task `:app:generateCorridorParityFixtures` is wired to regenerate
    `parity/corridor-core.json`.
  - `scripts/generate-corridor-parity-fixtures.py` remains available for later
    Android/Kotlin reference maintenance, outside the current iOS worktree.
    Do not install or select a JDK as part of this iOS V0b slice; run Android
    parity later in an Android/Docker context if needed.

## Local Code Gate

Run:

```bash
scripts/verify-ios-s0-local.sh
```

Expected result on this machine: structural checks pass and
`xcodebuild -project ios/Roana/Roana.xcodeproj -scheme Roana -destination
'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` passes.

## Deferred Hardware Proof

The following physical-device acceptance items remain unproven until the iPhone
is available again for launch/log capture:

- App launches on the physical iPhone after install.
- Permission prompt appears on first launch.
- Denied permission produces a clear non-crashing app state.
- Granted permission starts preview.
- Preview orientation matches the physical device orientation used for testing.
- A 60-second physical-device run produces repeated `roana_ios_frame_stats`.
- No backlog accumulates before model inference exists.
- Entering background stops camera work; returning foreground restarts cleanly.
- V0b corridor physical run produces YOLO, Depth Anything, Vision orientation,
  corridor feedback, fail-safe STOP, p95 <= 100 ms, and thermal <= fair evidence.

Latest physical-device progress:

- Signed V0b app build succeeded with command-line-only
  `DEVELOPMENT_TEAM=XP2NFR9M33`; the team ID is not committed to the project.
- `xcrun devicectl device install app --device
  A85B7E8D-1EDD-573F-9C50-BC76B9FB8E03 .../Roana.app` installed
  `app.roana.ios` successfully.
- Launch with `--roana-enable-corridor --roana-debug-fail-safe-stop` did not
  reach the app because CoreDevice reported the iPhone unavailable/offline.
  The failed launch log is local-only and is not a V0b proof artifact.

Acceptance artifact target:

```text
logs/ios-skeleton-<timestamp>.log
```

Machine-check the artifact with:

```bash
scripts/analyze-ios-log.py --log logs/ios-skeleton-<timestamp>.log --min-run-seconds 60 --require-background-stop 1 --require-background-cycle 1 --require-orientation 1 --require-idle-timer 1
```

Or use the physical-run wrapper:

```bash
scripts/verify-ios-device-log.py --gate s0 --log logs/ios-skeleton-<timestamp>.log
```

To create the canonical artifact and verify it in one step after collecting
raw app logs:

```bash
scripts/capture-ios-device-log.py --gate s0 < raw-ios-device.log
```

For the denied-permission S0 artifact, capture the launch after denying camera
permission and run:

```bash
scripts/verify-ios-device-log.py --gate s0-denied --log logs/ios-permission-denied-<timestamp>.log
```

Or capture and verify the denied artifact in one step:

```bash
scripts/capture-ios-device-log.py --gate s0-denied < raw-ios-permission-denied.log
```

After model assets are available, use `scripts/verify-ios-device-log.py --gate
v0a` for the YOLO-only speech artifact and `scripts/verify-ios-device-log.py
--gate v0b` for the corridor artifact. When calling the analyzer directly for
V0b, require YOLO, depth, Vision orientation, corridor feedback, inference,
`--max-p95-ms 100`, and `--max-thermal-state fair`; do not require generic
`roana_ios_speech status=queued` because corridor feedback owns V0b speech. The
physical-run wrapper applies the V0a/V0b model-description requirements,
V0a/V0b Vision orientation requirements, and the V0b cadence/thermal
requirements by default.

Before running model-backed iOS V0a/V0b gates, check the local asset contract:

```bash
scripts/check-ios-model-assets.py --require-present
```

Use the matching shared Xcode scheme for each device run: `Roana` for S0,
`Roana-V0a-YOLO` for V0a, and `Roana-V0b-Corridor` for V0b.

When the iPhone is available again, run the one-command V0b physical wrapper.
Keep the team ID in the environment only:

```bash
ROANA_IOS_DEVELOPMENT_TEAM=XP2NFR9M33 scripts/run-ios-v0b-physical.py
```

The wrapper checks model assets and device readiness, builds
`Roana-V0b-Corridor`, installs the signed app, launches `app.roana.ios` with
`--roana-enable-corridor --roana-debug-fail-safe-stop`, then captures and
verifies the V0b log through `scripts/capture-ios-device-log.py`. It blocks
with `iphone_device_available` while CoreDevice reports the phone as
offline/unavailable.

## No-Touch Scope

- Do not add real iOS Core ML model assets, benchmark claims, or performance
  gates until iOS-S0 builds under full Xcode and runs on a physical iPhone.
- Do not add large Core ML model artifacts directly to git; keep generated
  `.mlmodelc` / `.mlpackage` outputs out of normal source commits unless Git
  LFS or an explicit model-fetch path is added.
- Do not commit user-recorded replay videos or private scene-derived metadata
  unless they have been reviewed and the project adopts an explicit fixture
  sharing policy.
- Do not treat the Swift corridor smoke as full anti-divergence proof; the
  JSON fixture now covers planner, fusion, depth-grid conversion, state-machine,
  pipeline, and feedback-dispatch cases, but regenerating that Android-derived
  fixture remains outside this iOS V0b worktree.
- Do not claim iPhone performance, preview orientation, signing, installation,
  or camera callback cadence until physical-device evidence exists.
- Do not resume Android QNN diagnosis while this iOS port slice is active.
