# V0 Implementation Active Status

Updated: 2026-05-30.

## Current State

- Active objective: implement `docs/plan/v0-implementation-plan.md` via
  `intuitive-flow`.
- Latest completed slice: Mac + Docker + ADB development is working, and a
  Snapdragon 8 Gen 2 phone exposed QNN DSP transport/skeleton setup failure
  before model-specific offload can be evaluated.
- Current V0b slice: QNN DSP transport diagnosis is active; do not add a CPU
  fallback performance profile until the QNN transport/skeleton root cause is
  known.
- Rebased onto `origin/main` after the QNN smoke-gate work. The acceleration
  research now tracks the Android speedup-library direction (LiteRT Next
  primary, ONNX Runtime QNN diagnostic, ExecuTorch later candidate) and the iOS
  port plan now tracks a skeleton-first iPhone test handoff.
- Proven locally:
  - `scripts/check-android-env.sh` passes host requirements.
  - `scripts/build-debug.sh` builds `app/build/outputs/apk/debug/app-debug.apk`.
  - On Apple Silicon macOS, the Docker Android build uses the `linux/amd64`
    Android image explicitly, while ADB can be resolved from either `PATH` or
    `~/.local/android-platform-tools/platform-tools/adb`.
  - `scripts/verify-v0a-device.sh` and `scripts/verify-v0b-device.sh` now run on
    macOS Bash without GNU `mapfile` or `timeout`.
  - `scripts/verify-v0a-device.sh` passed on Xiaomi `2106118C` / Android 14.
  - Skeleton proof artifact: `logs/v0a-device-20260529T084255Z.log` contains
    `tts_init status=success`, `tts_event`, `camera_bound`, and sustained
    `frame_stats` with `gap_count=0`.
  - TFLite proof artifact: `logs/v0a-device-20260529T090726Z.log` contains
    `camera_bound`, `tts_event`, sustained `frame_stats`, and repeated
    `yolo_inference` lines with no `yolo_error`.
  - Detection-to-TTS proof artifact: `logs/v0a-device-20260529T091205Z.log`
    contains `debug_person_detection_proof`, `message=person_ahead`, sustained
    `frame_stats`, and repeated `yolo_inference` lines with no `yolo_error`.
  - QNN/fallback proof artifact: `logs/v0a-device-20260529T092038Z.log`
    contains `qnn_probe`, `qnn_capabilities`, a QNN delegate creation attempt,
    `reason=qnn_interpreter_failed`, and continued CPU/XNNPACK
    `yolo_inference` with no `yolo_error`.
  - Depth smoke proof artifact: `logs/v0a-device-20260529T093023Z.log`
    contains `qnn_probe precision=fp16`, `htp_fp16=false`,
    `reason=qnn_fp16_unavailable`, and `depth_smoke status=loaded` for the
    `[1,518,518,3] -> [1,518,518,1]` Depth Anything V2 TFLite model.
  - Corridor planner proof: Docker Android `:app:testDebugUnitTest` passes
    `CorridorPlannerTest` for straight, left, right, near-obstacle STOP,
    Depth Anything-sized downsampling, 3-frame state-machine confirmation,
    immediate STOP, frame-loss STOP, and low-confidence STOP.
  - Depth-to-planner proof artifact: `logs/v0a-device-20260529T094954Z.log`
    contains `depth_plan status=ok`, `decision=RIGHT`, `state=RIGHT`,
    `path_cells=15`, and `elapsed_ms=14904.30` after CPU fallback.
  - V0b gate artifact: `logs/v0b-device-20260529T095818Z.json` records the
    current device as `target_soc=false`, `fp16_htp=false`, `depth_fps=0.071`,
    and `gap_count=166`; the gate correctly fails instead of treating this
    Snapdragon 888 fallback run as a V0b corridor pass.
  - Corridor feedback dispatch is wired so the debug depth-plan state can emit
    a `corridor_feedback` log line and route the stable command to Android
    `TextToSpeech`. Local unit tests cover the dispatcher; real-speaker proof
    is deferred until a phone is available again.
  - The V0a/V0b device verifiers require `corridor_feedback status=spoken`
    when the debug depth-plan gate is enabled, so the next phone run can
    machine-check planner/state feedback instead of relying on a manual listen.
  - Depth Anything input preprocessing and one-shot inference are split into
    reusable components. Local tests cover center-crop resizing, RGB float input
    layout, and flattening `[1,518,518,1]` output into the planner depth map.
  - `CorridorPipeline` now owns the reusable depth-map -> planner -> state
    transition, with optional feedback dispatch. Unit tests cover 3-frame
    confirmation and feedback event emission through the same pipeline used by
    the debug depth smoke gate.
  - `CorridorGridFusion` combines Depth Anything output and YOLO detections into
    the 15x15 planner grid. Local tests cover high-confidence center detections
    forcing STOP and low-confidence detections leaving the depth corridor alone.
  - A debug-gated live corridor loop can route CameraX frames through the shared
    Depth Anything runner and corridor pipeline. The V0b verifier uses this
    `corridor_live` evidence for depth FPS instead of the older synthetic
    one-shot smoke path.
  - `scripts/verify-v0b-device.sh` has an opt-in `RUN_THERMAL_GATE=1` mode for
    the 30-minute live-corridor thermal check. By default it still stops after
    the short performance gate and reports thermal proof as pending.
  - The same verifier now requires explicit known-corridor blindfold test
    evidence before it can return `passed`; use `CORRIDOR_TEST_RESULT=passed`
    after a sighted-spotter run.
  - V0 privacy/product boundaries are covered by local tests: the manifest may
    request only camera permission, backup stays disabled, source code is
    checked for common network or frame-storage APIs, and out-of-scope crosswalk,
    identity, cloud, and VLM features are blocked by regression tokens.
  - V0b log-gate parsing is now centralized in `scripts/analyze-v0b-log.py` and
    covered by offline regression tests. The device verifier still owns ADB and
    thermal orchestration, but local tests can now exercise target-SoC, FP16
    HTP, depth FPS, live corridor frame-count, corridor feedback, frame-gap, and
    thermal-log decisions without requiring a phone.
  - Live corridor safety now routes CameraX frame gaps and live depth failures
    through the same fail-safe STOP state-machine path used by planner tests, so
    missing frames or uncertain live geometry can produce STOP feedback instead
    of only writing a log line.
  - The Depth Anything runner now reuses a preallocated input `ByteBuffer` for
    live frame inference, removing one per-frame direct buffer allocation from
    the CameraX -> depth path.
  - Live Depth Anything RGB frame conversion now reads `YUV_420_888` camera
    planes directly with rotation handling, avoiding the previous
    YUV -> JPEG -> Bitmap -> RGB frame round trip in the V0b depth path.
  - The live Depth Anything runner now feeds the preprocessor from a rotated YUV
    sampler, avoiding the intermediate full-frame RGB `IntArray` allocation
    before writing the model input tensor.
  - The live Depth Anything runner now also builds the 15x15 corridor grid
    directly from the TFLite output tensor, avoiding the intermediate 518x518
    flattened depth-map allocation in the V0b live loop.
  - Depth output aggregation now computes min/max and 15x15 cell sums in one
    pass over the TFLite output tensor before normalizing the 225 grid cells.
  - The live CameraX corridor loop now calls a grid-only Depth Anything
    inference path, so it no longer allocates a flattened 518x518 depth map when
    the next step only needs the 15x15 corridor grid.
  - The live YOLO detector now fills its 640x640 UINT8 input tensor directly
    from rotated CameraX `YUV_420_888` planes, removing the previous
    YUV -> JPEG -> Bitmap -> `IntArray` path from the real-time analysis loop.
  - YOLO inference failures now clear the last detection and route the live
    corridor loop through the same `low_confidence` fail-safe STOP path, so a
    stale detection cannot keep influencing depth/detection fusion after an
    uncertain detector frame.
  - The corridor planner now memoizes the best path from each 15x15 grid cell
    and covers an all-safe-grid case, avoiding exponential DFS path enumeration
    while preserving straight/left/right corridor decisions.
  - A debug-gated safe-stop proof can force the same `low_confidence` fail-safe
    path used by live depth errors and verify spoken `STOP` feedback. The V0b
    analyzer now requires this proof separately from normal corridor feedback,
    checks the log key/value fields for `low_confidence`, `STOP`, and
    `message=stop`, and only treats LEFT/STRAIGHT/RIGHT spoken feedback as
    guidance feedback, so a future target-phone run must prove both guidance
    feedback and STOP-on-uncertainty behavior.
  - The V0b target-device analyzer recognizes Snapdragon 8 Gen 2/3/Elite-class
    markers and Dimensity 9300/9400 platform markers, while still rejecting
    older MediaTek platforms in regression tests.
  - The V0b thermal analyzer now parses `dumpsys thermalservice` status values
    from before/after the 30-minute run and fails thermal proof on Android
    severe, critical, emergency, or shutdown status, so an overheated target
    phone cannot pass on FPS metrics alone.
  - Current target-class device: Xiaomi `2211133C` / `SM8550` (`kalama`,
    Snapdragon 8 Gen 2), Android 16 / HyperOS `OS3.0.307.0.WMCCNXM`.
  - V0a proof artifact on the Snapdragon 8 Gen 2 phone:
    `logs/v0a-device-20260529T135914Z.log`. It proves the basic
    CameraX/TFLite/TTS/safe-stop loop, but YOLO fell back to CPU/XNNPACK after
    QNN delegate apply failed. The observed YOLO timing was about 1.65s average
    per inference, with repeated CameraX frame gaps.
  - V0b live corridor proof attempt on the same phone:
    `logs/v0a-device-20260529T140409Z.log`. QNN reported
    `htp_quantized=true htp_fp16=true`, but both YOLO and Depth Anything fell
    back to CPU, so live corridor produced repeated `frame_loss` safe-stop
    evidence and no `corridor_live status=ok` frames.
  - New QNN model compatibility smoke artifact:
    `logs/qnn-smoke-20260529T152658Z.log`. It records model-specific tensor
    metadata and separate QNN delegate failures:
    YOLO `UINT8[1,640,640,3] -> INT8` multi-output quantized tensors and Depth
    Anything `FLOAT32[1,518,518,3] -> FLOAT32[1,518,518,1]` both fail with
    `Failed to apply delegate: Restored original execution plan after delegate
    application failure`.
  - Strict QNN smoke gate artifact: `logs/qnn-smoke-20260529T152836Z.log`.
    `scripts/verify-qnn-smoke-device.sh` correctly returns failed with
    `QNN delegate rejected model(s): yolo depth`.
  - Full logcat QNN probe artifact: `logs/qnn-smoke-full-20260529T154349Z.log`.
    Native `QnnDsp` logs show `loadRemoteSymbols failed with err 4000`,
    `Failed to create transport for device`, `Failed to load skel`, and
    `Transport layer setup failed: 14001` before the TFLite interpreter reports
    delegate application failure.
  - The QNN smoke gate now captures full logcat by default and classifies this
    case as a DSP transport/skeleton setup failure. Artifact
    `logs/qnn-smoke-20260529T155527Z.log` returns
    `QNN DSP transport/skeleton setup failed before model-specific offload:
    yolo depth`.

## Stop Condition

V0a is complete. V0b has verified backend fallback, Depth Anything asset
loading, reusable Depth Anything preprocessing/inference, Depth Anything-sized
downsampling plus YOLO detection fusion into the 15x15 planner, a reusable
corridor pipeline, and a pure-Kotlin 3-frame command confirmation state
machine. A debug-gated live CameraX -> Depth Anything -> corridor pipeline path
exists, but the current target-class Snapdragon 8 Gen 2 phone fails QNN DSP
transport/skeleton setup before model-specific delegate compatibility can be
evaluated, then falls back to CPU. Emergency STOP behavior for near obstacles,
frame loss, and low confidence is covered in unit tests. The full V0b corridor
demo is not proven on this device because QNN HTP is not operational yet,
despite device HTP quantized/fp16 capability being reported as available.

## Next Agent-Owned Step

Use `scripts/verify-qnn-smoke-device.sh` as the next machine gate while
diagnosing QNN compatibility. The next agent-owned step is to determine whether
the QNN DSP transport/skeleton failure is caused by packaging/signing of HTP
skel/stub libraries, unsigned PD requirements, dependency/version mismatch, or
QNN delegate option setup. The research follow-up order is: package/layout
audit, QNN delegate-option spike, LiteRT Next `CompiledModel` spike, Qualcomm AI
Hub context-binary spike, then ONNX Runtime QNN cross-check if needed. Only
after transport succeeds should model export/operator support, tensor layout,
and quantization format be treated as the primary suspects. Do not add a
lower-performance CPU fallback profile before that root cause is known. After
QNN accepts both models, rerun `scripts/verify-v0b-device.sh` for the short
live-corridor gate; only then run `RUN_THERMAL_GATE=1
scripts/verify-v0b-device.sh` and the known-corridor sighted-spotter proof.

## No-Touch Scope

- Do not start BLE, outdoor navigation, cloud/VLM, or custom training work in
  V0.
- Do not add fallback-performance tuning for the Snapdragon 8 Gen 2 failure
  until the QNN delegate rejection is diagnosed.
