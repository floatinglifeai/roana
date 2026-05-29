# V0 Implementation Active Status

Updated: 2026-05-29.

## Current State

- Active objective: implement `docs/plan/v0-implementation-plan.md` via
  `intuitive-flow`.
- Latest completed slice: V0b device gate now requires a debug safe-stop proof
  that low-confidence uncertainty produces spoken STOP feedback.
- Current V0b slice: Snapdragon 8 Gen 2+ device proof is pending hardware.
- Proven locally:
  - `scripts/check-android-env.sh` passes host requirements.
  - `scripts/build-debug.sh` builds `app/build/outputs/apk/debug/app-debug.apk`.
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
  - Current device: Xiaomi `2106118C` / `SM8350` (`lahaina`, Snapdragon 888).
    It is useful for fallback proof, but below the V0b Depth Anything
    performance target of Snapdragon 8 Gen 2+.

## Stop Condition

V0a is complete. V0b has verified backend fallback, Depth Anything asset
loading, reusable Depth Anything preprocessing/inference, Depth Anything-sized
downsampling plus YOLO detection fusion into the 15x15 planner, a reusable
corridor pipeline, and a pure-Kotlin 3-frame command confirmation state
machine. A debug-gated live CameraX -> Depth Anything -> corridor pipeline path
exists, but CPU fallback took about 14.9s for one synthetic depth frame on this
phone. Emergency STOP behavior for near obstacles, frame loss, and low
confidence is covered in unit tests. The full V0b corridor demo is not proven
on this device because FP16 HTP is unavailable and the phone is below the
target performance class.

## Next Agent-Owned Step

Run the debug live-corridor gate on a Snapdragon 8 Gen 2+ class device with
FP16 HTP available when a phone is available again. After the short gate passes,
run `RUN_THERMAL_GATE=1 scripts/verify-v0b-device.sh` to prove the CameraX frame
-> Depth Anything -> corridor pipeline reaches the >=10 FPS target without
30-minute thermal regression. After a known-corridor blindfold test with a
sighted spotter passes, rerun with `CORRIDOR_TEST_RESULT=passed` and brief
`CORRIDOR_TEST_NOTES`.
Use `scripts/verify-v0b-device.sh` as the machine gate before any known-corridor
blindfold test; it must pass the target SoC, FP16 HTP, depth FPS, frame-gap, and
thermal prerequisites before V0 can close.

## No-Touch Scope

- Do not run ADB or real-device gates while the phone is unavailable.
- Do not start BLE, outdoor navigation, cloud/VLM, or custom training work in
  V0.
