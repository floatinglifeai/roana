# V0 Implementation Active Status

Updated: 2026-05-31.

## Current State

- Active objective: implement `docs/plan/v0-implementation-plan.md` via
  `intuitive-flow`.
- Active follow-up objective: implement
  `docs/plan/android-litert-validation-plan.md` via `intuitive-flow` as a
  debug-only validation path, while preserving the current QNN-required
  production runtime.
- Latest completed slice: the Snapdragon 8 Gen 2 live V0b path now runs YOLO
  and Depth Anything on QNN HTP, passes the short machine gate, and passes the
  30-minute thermal live-corridor gate without severe frame gaps.
- Current V0b slice: the remaining proof is the known-corridor
  sighted-spotter run. Android production inference is now QNN-required:
  missing QNN capability, delegate creation failure, or delegate application
  failure must fail the gate instead of silently using CPU/XNNPACK. Do not add a
  CPU fallback performance profile; remaining work should keep diagnosing actual
  Android/iOS support gaps.
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
  - Historical QNN diagnostic artifact: `logs/v0a-device-20260529T092038Z.log`
    showed the earlier CPU/XNNPACK fallback after QNN delegate application
    failure. That fallback path has since been removed from production runtime.
  - Historical Depth smoke artifact: `logs/v0a-device-20260529T093023Z.log`
    showed `htp_fp16=false` on a non-target device. Current production runtime
    treats missing QNN capability as unavailable rather than falling back to CPU.
  - Corridor planner proof: Docker Android `:app:testDebugUnitTest` passes
    `CorridorPlannerTest` for straight, left, right, near-obstacle STOP,
    Depth Anything-sized downsampling, 3-frame state-machine confirmation,
    immediate STOP, frame-loss STOP, and low-confidence STOP.
  - Historical Depth-to-planner artifact: `logs/v0a-device-20260529T094954Z.log`
    contained `depth_plan status=ok`, `decision=RIGHT`, `state=RIGHT`,
    `path_cells=15`, and `elapsed_ms=14904.30` on CPU fallback. Current
    production runtime no longer accepts that path.
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
  - `scripts/record-v0b-corridor-test.sh` wraps the V0b verifier for the
    final known-corridor blindfold run and requires `CORRIDOR_TEST_NOTES`, so
    the machine artifact carries sighted-spotter context instead of only an
    environment variable.
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
  - New true-device QNN package/layout probe:
    `logs/qnn-probe-20260529T235359Z.log`. It confirms the APK and installed
    native library directory contain `libQnnHtp.so`, `libQnnHtpPrepare.so`,
    the HTP V68/V69/V73/V75/V79/V81 skel/stub libraries, `libQnnSystem.so`,
    and `libQnnTFLiteDelegate.so`; camera permission is granted and GPU debug
    layers are off. The failure is now narrower than a missing packaged skel:
    QNN opens the app-packaged `libQnnHtpV73Stub.so`, but that stub cannot
    resolve `libcdsprpc.so` inside the app linker namespace, even though the
    device exposes `/vendor/lib64/libcdsprpc.so`. Explicit QNN library/skel
    paths do not change the failure; the probe now returns
    `QNN HTP stub is present, but libcdsprpc.so is not visible in the app
    linker namespace`.
  - QNN transport fix: the app manifest now declares optional
    `<uses-native-library android:name="libcdsprpc.so" android:required="false" />`,
    which makes the vendor FastRPC library visible to the app linker namespace
    on the Xiaomi `SM8550` target while preserving installability on devices
    without that public native library. After this change, the default QNN smoke
    gate artifact `logs/qnn-smoke-20260530T000545Z.log` passes for both YOLO
    and Depth Anything on `qnn_htp` using explicit QNN library/skel paths.
  - Live V0b QNN artifact: `logs/v0a-device-20260530T001530Z.log` proves the
    real CameraX live corridor path now selects `qnn_htp` for both quantized
    YOLO and FP16 Depth Anything, and emits `corridor_live status=ok` frames.
    The remaining V0b machine gate fails on performance and scheduling rather
    than transport: analyzer output reports `depth_elapsed_ms=174.69`,
    `depth_fps=5.724`, `gap_count=34`, and no normal guidance feedback because
    repeated frame-loss safe stops keep resetting the 3-frame guidance
    confirmation.
  - QNN model timing artifact: `logs/qnn-smoke-20260530T002450Z.log`. With
    warm QNN interpreters and zero inputs, YOLO averages `2.52 ms` and Depth
    Anything averages `53.47 ms` across 5 iterations. This proves the remaining
    V0b performance blocker is not steady-state QNN inference; it is live
    CameraX/analyzer work around the model, especially depth input preparation
    and serialized scheduling.
  - Live analyzer timing artifact: `logs/v0a-device-20260530T003629Z.log`.
    Stage timing showed the original live bottleneck was outside QNN model
    execution: Depth input preparation averaged `896.83 ms`, YOLO input
    preparation averaged `1145.85 ms`, while QNN model execution remained much
    lower.
  - Live V0b performance fix artifact:
    `logs/v0a-device-20260530T011426Z.log`. The short V0b device gate now
    passes on the Snapdragon 8 Gen 2 phone with QNN HTP active:
    `depth_elapsed_ms=53.37`, `depth_fps=18.737`,
    `depth_input_elapsed_ms=16.74`, `depth_grid_elapsed_ms=7.23`,
    `corridor_total_elapsed_ms=78.33`, `yolo_total_elapsed_ms=113.25`,
    `live_corridor_count=356`, `gap_count=0`, normal STRAIGHT guidance
    feedback spoken, and the low-confidence safe-stop proof spoken. The fix
    keeps the no-CPU-fallback direction: it reduces live CameraX preprocessing
    and scheduling overhead by using direct-buffer output for Depth Anything,
    heap scratch plus bulk copies for live YUV input/output conversion, a
    depth-specific luma fast path, YOLO/depth frame isolation, and a frame-loss
    policy that distinguishes startup/light CameraX jitter from severe runtime
    frame loss.
  - Sustained V0b thermal proof artifact:
    `logs/v0a-device-20260530T024149Z.log`, launched by
    `RUN_THERMAL_GATE=1 REQUIRE_CORRIDOR_TEST=0 LOG_SECONDS=60
    ./scripts/verify-v0b-device.sh` after reducing the live depth cadence to
    leave CameraX analyzer headroom. The 30-minute gate passed on the same
    Snapdragon 8 Gen 2 phone with `thermal_gap_count=0`,
    `thermal_live_corridor_count=8850`, `thermal_depth_fps=18.646`,
    `thermal_tail_depth_fps=18.692`, and thermal status `none` before and
    after. The short warm gate in the same verifier also passed with
    `gap_count=0`, normal STRAIGHT guidance feedback spoken, and
    low-confidence safe STOP feedback spoken.
  - Android acceleration-library metadata probe artifact:
    `logs/android-acceleration-libs-20260530T032748Z.json`. It confirms the
    tracked Maven candidates are currently resolvable:
    `com.google.ai.edge.litert:litert` latest `2.1.5`,
    `com.microsoft.onnxruntime:onnxruntime-android` latest `1.26.0`,
    `com.microsoft.onnxruntime:onnxruntime-android-qnn` latest `1.26.0`, and
    `org.pytorch:executorch-android` latest `1.3.1`. Decision remains to keep
    the passing QNN HTP delegate as the production path, reserve LiteRT for an
    optional broader-device spike, use ORT QNN only as a diagnostic cross-check,
    and defer ExecuTorch migration.
  - CPU fallback cleanup artifact set: Docker `:app:testDebugUnitTest`,
    `scripts/build-debug.sh`, `scripts/verify-qnn-smoke-device.sh` with
    artifact `logs/qnn-smoke-20260530T045117Z.log`, and the short V0b gate
    artifact `logs/v0a-device-20260530T044604Z.log`. Production inference now
    selects `qnn_htp` for quantized YOLO and FP16 Depth Anything or fails with
    `selected=unavailable`; `InferenceBackendPolicyTest` blocks reintroducing
    the old CPU fallback selectors, XNNPACK runtime option, and nullable
    delegate-state fields into production runtime. The QNN smoke metadata-only
    XNNPACK interpreter remains diagnostic-only and is not a runtime fallback.
  - LiteRT validation Phase 0 review decision: pin
    `com.google.ai.edge.litert:litert` to `2.1.5`, prefer a debug-only app path,
    but use an isolated sample module if the LiteRT dependency conflicts with
    the current QNN app classpath. The smoke code uses the `CompiledModel` API
    through `Accelerator.NPU`,
    `Environment.create(BuiltinNpuAcceleratorProvider(...))`, input/output
    buffer allocation, and `run(...)`. The first verifier artifact must be
    `logs/litert-smoke-*.log`; it may pass only with explicit
    `litert_backend selected=npu` and loaded/timing evidence, and it must fail
    on unavailable, missing runtime, rejected model, or unproven backend proof.
  - LiteRT validation Phase 0/1 implementation artifact set: production
    `scripts/build-debug.sh` passes and still builds only
    `app/build/outputs/apk/debug/app-debug.apk`; the isolated
    `scripts/build-litert-smoke-debug.sh` gate builds
    `litert-smoke/build/outputs/apk/debug/litert-smoke-debug.apk`; Docker
    `:app:testDebugUnitTest` passes; Python verifier tests pass via
    `python3 -m unittest scripts/test_probe_android_acceleration_libs.py
    scripts/test_analyze_v0b_log.py`; `scripts/verify-litert-smoke-device.sh`
    currently returns `blocked` before artifact capture because ADB lists no
    connected device. On 2026-05-30, this was rechecked with the verifier's
    fallback host ADB at
    `/Users/dongxu/.local/android-platform-tools/platform-tools/adb`; `adb
    devices` still returned no attached devices, and the smoke verifier returned
    `status=blocked` with no `logs/litert-smoke-*.log` artifact. Next device
    run should use:
    `BUILD_FIRST=0 INSTALL_FIRST=1 MODEL=all LITERT_ACCELERATOR=npu
    LITERT_TIMING_ITERATIONS=1 LOG_SECONDS=20
    scripts/verify-litert-smoke-device.sh`.
  - LiteRT validation Phase 1 device result:
    `logs/litert-smoke-20260530T122948Z.log` from Xiaomi `2211133C` / `fuxi` /
    SM8550 / Android 16 / HyperOS OS3.0 using LiteRT `2.1.5`.
    `scripts/verify-litert-smoke-device.sh` installed the isolated smoke APK
    and returned `failed` by design with decision
    `LiteRT backend proof unproven for model(s): yolo depth.` YOLO logged
    `litert_backend requested=npu`, `status=loaded ... backend=unproven`, and
    one timing pass at `avg_ms=65.21`; Depth Anything logged the same unproven
    backend status and one timing pass at `avg_ms=1858.92`. Both runs also
    reported `No dispatch library found` under the smoke APK native library
    directory. Decision: stop the LiteRT validation at plan Stop Condition 4,
    keep the production Android runtime on the proven TFLite + QNN HTP path,
    and do not proceed to Phase 2 QNN comparison or a live V0b LiteRT trial
    without a future LiteRT API/runtime path that can prove actual NPU backend
    selection.
  - LiteRT Qualcomm runtime follow-up: packaging
    `libLiteRtDispatch_Qualcomm.so` and QNN V73 libraries moved the failure
    past the earlier missing-dispatch blocker. `logs/litert-smoke-20260530T134350Z.log`
    with LiteRT `2.1.1` exposed a QNN runtime mismatch
    (`Qnn System library version 1.10.0 ... LiteRT using is 1.6.0`). Replacing
    `libQnnHtp.so`, `libQnnSystem.so`, and `libQnnHtpV73Stub.so` with official
    EfficientDet V73 sample binaries removed that version warning and reached
    FastRPC CDSP user-PD creation plus `libQnnHtpV73Skel.so` open, but
    `logs/litert-smoke-20260530T141116Z.log` still failed at QNN device
    creation (`failed to call device create, 1008`) and fell back to XNNPACK.
    Adding the official MobileNet Qualcomm compiler plugin and building with
    LiteRT `2.1.4` made an intermediate plugin path load, resolve, and
    initialize, but `logs/litert-smoke-20260530T142110Z.log` then failed JIT setup because the
    V73 `libQnnSystem.so` is version `1.6.0` while the plugin requires at least
    `1.8.0`. The MobileNet sample includes a fuller Qualcomm runtime set with
    `libQnnHtpPrepare.so`, but for V79, not this SM8550/V73 device. The best
    matched JIT attempt used LiteRT `2.1.1`, the official
    `litert_npu_runtime_libraries_jit.zip` V73 compiler/dispatch libraries,
    and QAIRT `2.41.0.251128` V73 QNN libraries including
    `libQnnHtpPrepare.so`. `logs/litert-smoke-20260530T144736Z.log` and
    `logs/litert-smoke-20260530T145843Z.log` show Qualcomm dispatch
    initialized (`Dispatch API vendor ID: Qualcomm`, QNN API build
    `v2.41.0.251128145156_191518`), FastRPC unsigned CDSP user-PD creation, and
    `libQnnHtpV73Skel.so` open. The JIT compiler still applied zero plugins:
    `failed to call device create, 14001`, then XNNPACK CPU fallback was
    observed. A default-provider control run in
    `logs/litert-smoke-20260530T150158Z.log` reproduced the same `14001`, so
    the explicit Qualcomm compatibility checker is not the cause. The official
    EfficientDet-Lite0 positive-control model reproduced the same failure in
    `logs/litert-smoke-20260530T153551Z.log`: Qualcomm dispatch initialized,
    `libQnnHtpV73Skel.so` opened, `QnnDevice_create` failed with `14001`, zero
    compiler plugins were applied, and XNNPACK CPU fallback occurred. The
    instrumented run `logs/litert-smoke-20260530T155100Z.log` confirmed the
    smoke APK contains the expected V73 LiteRT/QNN native libraries and can
    preload `QnnSystem`, `QnnHtp`, `QnnHtpPrepare`, `QnnHtpV73Stub`,
    `LiteRtDispatch_Qualcomm`, and `LiteRtCompilerPlugin_Qualcomm`; it still
    produced zero `QnnDevice_create done`, zero `QnnContext_create`, zero
    `QnnGraph_execute`, and the same `14001` device-create failure. A
    same-session production QNN control,
    `logs/qnn-smoke-20260530T155245Z.log`, passed with
    `QNN_VARIANT=explicit_paths`: `QnnDevice_create done` appeared twice,
    `QnnGraph_execute` appeared 136 times, and YOLO timing was `2.79 ms`.
    Current classification: LiteRT Next is not proven unusable globally, but
    Roana's current SM8550/V73 Qualcomm JIT path is unavailable for product use
    and should not be compared by timing. Next directions are an
    AOT/precompiled LiteRT Qualcomm sample/model path that avoids on-device JIT,
    an official Qualcomm sample APK/model using Play Feature Delivery-style
    runtime modules with strict NPU-required logging, or a newer/more
    device-matched V73 runtime from Google/Qualcomm.
  - Official LiteRT sample control: the official EfficientDet Kotlin NPU sample
    was built from `/tmp/litert-samples` after adding the same
    `android.experimental.enableDeviceTargetingConfigApi=true` flag used by the
    other NPU samples. Its AAB packaged the V73 Qualcomm dynamic-feature runtime
    with `libLiteRtDispatch_Qualcomm.so`, `libLiteRtCompilerPlugin_Qualcomm.so`,
    `libQnnHtpPrepare.so`, and the V73 QNN libraries, but MIUI blocked fresh
    `com.example.*` installs with `INSTALL_FAILED_USER_RESTRICTED`. A temporary
    base-APK variant using application id `com.roana.litertsmoke` installed
    successfully; the original smoke APK was reinstalled afterward. The
    PID-filtered official-sample artifact
    `logs/litert-official-efficientdet-pidfiltered-20260530T162507Z.log` shows
    Java-level `Selected LiteRT backend=NPU`, but native logs show
    `NPU accelerator could not be loaded and registered:
    kLiteRtStatusErrorInvalidArgument` followed by
    `Created TensorFlow Lite XNNPACK delegate for CPU`; no Qualcomm dispatch or
    QNN graph evidence appears in that process. This confirms the log rule:
    LiteRT Java/backend labels and timings are not enough; require native
    Qualcomm dispatch plus `QnnDevice_create done` and `QnnGraph_execute`.
  - Provider/options matrix: the smoke app now accepts
    `LITERT_NPU_PROVIDER=qualcomm|default|none` and
    `LITERT_QUALCOMM_OPTIONS=full|minimal|none`. EfficientDet runs
    `logs/litert-smoke-20260530T163039Z.log` (`qualcomm/full`),
    `logs/litert-smoke-20260530T163119Z.log` (`default/minimal`), and
    `logs/litert-smoke-20260530T163158Z.log` (`default/none`) all reached
    Qualcomm dispatch, created a FastRPC unsigned CDSP user PD, opened
    `libQnnHtpV73Skel.so`, then failed at `QnnDevice_create` error `14001` with
    zero QNN context/graph execution and XNNPACK CPU fallback. This rules out
    Roana model export, explicit Qualcomm checker selection, and full debug
    Qualcomm options as primary causes for the current JIT failure. Remaining
    agent-checkable directions are AOT/AI Pack/precompiled Qualcomm LiteRT
    assets or a newer/device-matched V73 runtime/provider package.
  - LiteRT AOT follow-up: the smoke APK now includes the precompiled
    `efficientdet_lite0_detection_Qualcomm_SM8550.tflite` asset. APK inspection
    shows `LiteRtStamp`, `Qualcomm`, `SM8550`, `DISPATCH_OP`, and
    `qnn_partition_0`, confirming this is a dispatch/context-binary model.
    `logs/litert-smoke-20260530T174119Z.log` with LiteRT Android core `2.1.1`,
    v2.1.1 Qualcomm dispatch/compiler-plugin libraries, and QAIRT
    `2.41.0.251128` V73 QNN libraries initialized Qualcomm dispatch, opened the
    V73 HTP skel, found `qnn_partition_0`, then failed at
    `Failed to create QNN context: 5000`. It produced zero
    `QnnContext_create` success and zero `QnnGraph_execute`. The same AOT
    context failure reproduced with `LITERT_QUALCOMM_OPTIONS=minimal`
    (`logs/litert-smoke-20260530T174441Z.log`) and `none`
    (`logs/litert-smoke-20260530T174520Z.log`), ruling out full debug/profiling
    Qualcomm options as the primary cause. A CPU control
    (`logs/litert-smoke-20260530T173822Z.log`) failed on `DISPATCH_OP`, as
    expected for a dispatch-only AOT asset. A same-session production QNN
    control (`logs/qnn-smoke-20260530T163540Z.log`) created QNN contexts twice
    and executed QNN graphs 140 times on the same phone, so the current evidence
    points to LiteRT AOT context-binary/runtime compatibility, not a global QNN
    context failure. The official AOT tutorial uses
    `ai-edge-litert-nightly` plus `ai-edge-litert-sdk-qualcomm-nightly`; local
    package resolution found `2.2.0.dev20260529`, but Qualcomm AOT compilation
    is Linux-x86-only, so this macOS arm64 host cannot directly rebuild a
    matched Qualcomm AOT artifact. Next LiteRT check: use Linux x86 to build a
    nightly Qualcomm AOT artifact with a matching Android runtime/provider, or
    use a Google/Qualcomm AI Pack/sample that ships both compiled model and
    runtime together.
  - LiteRT nightly AOT control: the Linux x86 Docker AOT compiler path now works
    with `ai-edge-litert-nightly==2.2.0.dev20260529` and
    `ai-edge-litert-sdk-qualcomm-nightly==2.2.0.dev20260529` in
    `roana-litert-aot-sm8550:20260531-libcxx`. The compiler needed host
    `libc++`/`libunwind`, `LD_LIBRARY_PATH` pointed at the SDK's
    `x86_64-linux-clang` QNN libs, and target
    `qnn_target.Target(qnn_target.SocModel.SM8550)`. It produced
    `build/litert-aot-sm8550/efficientdet_lite0_detection_Qualcomm_SM8550_apply_plugin.tflite`,
    4.7 MB, SHA256
    `fd211463599e07c431cd9713f7140124205b0a63601fd7488c264635db047466`, with
    `LiteRtStamp`, `Qualcomm`, `SM8550`, `DISPATCH_OP`, and `qnn_partition_0`
    markers.
  - Packaged nightly AOT smoke artifacts:
    `logs/litert-smoke-20260531T012554Z.log` and
    `logs/litert-smoke-20260531T014103Z.log`. The smoke APK was rebuilt with
    `LITERT_EXTRA_ASSET_DIR="$PWD/build/litert-aot-sm8550/assets"` and
    `LITERT_VERSION=2.1.1`; it contains the AOT asset and V73 Qualcomm libs.
    On Xiaomi `2211133C` / SM8550, `MODEL=efficientdet_aot` loaded the asset,
    initialized Qualcomm dispatch (`QNN API version 2.35.0`, build
    `v2.46.0.260424121129`), found `qnn_partition_0`, created an unsigned CDSP
    user PD, opened `libQnnHtpV73Skel.so`, and emitted smoke-PID `RPC (execute)`
    and `QNN accelerator (execute)` profiling. The first run completed one
    EfficientDet timing iteration at `20.63 ms`; the repeat run used five
    timing iterations, emitted six smoke-PID QNN accelerator execute profiling
    entries for one load run plus five timed runs, and averaged `21.55 ms`
    (`20.46 ms` min, `22.07 ms` max). The analyzer now classifies both as
    `aot_accelerator_execute_evidence_with_runtime_warnings`, not plain
    `runtime_mismatch`.
  - Roana LiteRT AOT compile and timing: the same Docker AOT path compiled
    Roana YOLO and Depth for SM8550. YOLO output
    `build/litert-aot-sm8550-roana/yolo/yolo11n-det-int8-smart_Qualcomm_SM8550_apply_plugin.tflite`
    is 3.0 MB, SHA256
    `9bbbc250e79128d7c502fef81a81b45d73b6c6ce92b5e854a096ddd44d2ae11d`, with
    `316 / 316` ops offloaded to one partition. Depth output
    `build/litert-aot-sm8550-roana/depth/depth_anything_v2_Qualcomm_SM8550_apply_plugin.tflite`
    is 50 MB, SHA256
    `30ba9e1b057dfd38eb4fe41b4c7e28dd66ffc72a21b378219a97d2f95016540d`, with
    `598 / 598` ops offloaded to one partition. The process is now scripted by
    `scripts/compile-litert-qualcomm-aot.sh`.
  - Roana LiteRT AOT device artifact:
    `logs/litert-smoke-20260531T022907Z.log`. The smoke APK was rebuilt with
    `LITERT_EXTRA_ASSET_DIR="$PWD/build/litert-aot-sm8550-roana/assets"` and
    `LITERT_VERSION=2.1.1`, then run with `MODEL=all_aot`,
    `LITERT_NPU_PROVIDER=qualcomm`, full Qualcomm options, and five timing
    iterations. The analyzer classifies the run as
    `aot_accelerator_execute_evidence_with_runtime_warnings`: the smoke PID
    initialized Qualcomm dispatch with QNN API `2.35.0`, found a QNN graph,
    opened the V73 HTP skel, created an unsigned CDSP user PD, and emitted 12
    smoke-PID `QNN accelerator (execute) time` entries plus RPC/cycle timing.
    Timings were YOLO AOT `13.60 ms` average (`13.26 ms` min, `14.11 ms` max,
    load `785.28 ms`) and Depth AOT `87.53 ms` average (`87.17 ms` min,
    `87.93 ms` max, load `213.92 ms`).
  - Fresh TFLite+QNN controls remain faster on the same phone:
    `logs/qnn-smoke-20260531T023528Z.log` records YOLO explicit-path QNN
    `3.74 ms` average across five iterations, and
    `logs/qnn-smoke-20260531T023627Z.log` records Depth explicit-path QNN
    `52.75 ms` average across five iterations. Earlier full-log native QNN
    controls remain the graph-execution evidence artifacts:
    `logs/qnn-smoke-20260530T155245Z.log` for YOLO (`2.79 ms`) and
    `logs/qnn-smoke-20260530T002450Z.log` for Depth (`53.47 ms`). Current
    performance conclusion: LiteRT AOT is about `3.64x` slower than the fresh
    YOLO TFLite+QNN control and `1.66x` slower than the fresh Depth control.
  - LiteRT AOT runtime caveat: the successful Roana AOT run still reports QNN
    runtime version warnings (`QnnSystem 1.10.0` vs LiteRT `1.6.0`, QNN API
    `2.35.0` vs LiteRT `2.31.0`, backend `5.46.0` vs LiteRT `5.41.0`), has an
    XNNPACK CPU delegate creation line, and lacks smoke-PID
    `QnnGraph_execute done status 0x0`. A controlled rebuild with the older
    v2.1.1/QAIRT `2.41.0.251128` V73 runtime removed the mismatch
    (`qnn_runtime_mismatch=false`) but failed both Roana AOT models at
    `Failed to create QNN context: 5000`
    (`logs/litert-smoke-20260531T025130Z.log`). Public artifact metadata still
    shows stable Android Maven latest `2.1.5`, while GitHub `v2.1.5` only
    publishes `litert_cc_sdk.zip`; the public Qualcomm Android runtime zip
    remains on `v2.1.1`. The missing piece is a matched Android Qualcomm
    dispatch/runtime bundle for the nightly QNN `2.35`/backend `5.46` stack.
  - LiteRT newer-version research result: the latest public `litert:2.1.5` is
    not proven to have worse NPU support, but it is incompatible with the public
    v2.1.1 Qualcomm dispatch/plugin libraries. `logs/litert-smoke-20260531T031238Z.log`
    and `logs/litert-smoke-20260531T032120Z.log` both fail before model
    execution because `libLiteRtDispatch_Qualcomm.so` and
    `libLiteRtCompilerPlugin_Qualcomm.so` cannot resolve
    `LiteRtQualcommOptionsGet`. Symbol inspection shows `litert:2.1.1`
    exports the old `LiteRtQualcommOptionsGet*` ABI, while `litert:2.1.5` uses
    the newer `LrtQualcommOptions*` C/C++ API. Replacing only the native QNN
    runtime with Qualcomm Maven `qnn-runtime:2.46.0` does not help, and
    `qnn-litert-delegate:2.46.0` contains the traditional TFLite delegate
    (`libQnnTFLiteDelegate.so`), not the LiteRT `CompiledModel` dispatch
    provider. Official AI Pack/runtime-module docs and samples point to
    Play-delivered AI Packs for models plus base/dynamic-feature native runtime
    libraries; the checked Qualcomm NPU samples still pin LiteRT `2.1.0` or
    `2.1.1`, and the C++ prebuilt NPU sample also requires the v2.1.1 Qualcomm
    dispatch zip. Current blocker is therefore public availability of a matched
    newer Qualcomm LiteRT dispatch/runtime package, not Roana model conversion
    or C++ versus Java API shape.
  - GitHub issue/PR cross-check for that blocker:
    `google-ai-edge/LiteRT#6889` requests AAR-matched prebuilt Qualcomm dispatch
    libraries and documents the same dispatch ABI mismatch class;
    `google-ai-edge/LiteRT#5592` and `#5594` show Snapdragon 8 Gen 2/3/Elite
    developers hitting missing compiler/dispatch, `No usable Dispatch runtime
    found`, and dispatch API mismatch; `google-ai-edge/LiteRT-LM#2079`, `#2020`,
    and `#2226` show the same native-library-dir, `libcdsprpc.so`,
    `LiteRtQualcommOptionsGet`, and QNN version-mismatch family on LiteRT-LM.
    LiteRT `main` remains active, with 2026-05-30 UTC merges and current
    Qualcomm source using `LrtQualcommOptions*` plus QAIRT `2.46.0.260424`; the
    problem is not removed support, but unreleased/missing matched Android
    provider packaging for public stable `2.1.5`.
  - Adjacent stack check: MediaPipe is worth monitoring for multi-model pipeline
    structure but does not replace the underlying LiteRT/QNN runtime problem;
    LiteRT-LM is worth tracking for future on-device LLM features but targets
    `.litertlm` Gemma-family models and has the same native dispatch/QNN
    packaging concerns.
  - LiteRT `main` source-built smoke: main at
    `2efe1c141bc6598f7dcae973c989b1bcba71fc11` was built for Android arm64 with
    Qualcomm enabled, producing `run_model`, `libLiteRt.so`,
    `libLiteRtDispatch_Qualcomm.so`, and `libLiteRtCompilerPlugin_Qualcomm.so`.
    The device bundle under `build/litert-main-2efe1c1-qairt246/device/` was
    pushed to `/data/local/tmp/litert-main-2efe1c1-qairt246` with QAIRT
    `2.46.0.260424` V73 libraries and the Roana AOT models. On Xiaomi
    `2211133C` / SM8550, C++ `run_model --accelerator=npu` passed for YOLO and
    Depth. `logs/litert-main-run-model-yolo-20260531T051859Z.log` and
    `logs/litert-main-run-model-depth-20260531T051911Z.log` both show
    `Context binary SDK version matches current SDK: 2.46.0`,
    `QnnDevice_create done`, `QnnContext_createFromBinary done successfully`,
    five `QnnGraph_execute done. status 0x0` entries, and five
    `QNN (execute) time` entries. C++ `run_model` timing averaged `3.106 ms`
    for YOLO and `47.977 ms` for Depth across five iterations. This proves the
    newer source stack can run and the issue is public Android provider
    packaging/release availability, not removed Qualcomm support. It is still
    not a production path until the same stack is available from a tagged
    release/Maven-compatible artifact and is integrated into the Android app
    without mixing ABI generations.
  - LiteRT `main` AAR attempt: upstream target `//litert/kotlin:litert` exists
    and is the right artifact shape for a coherent Java/Kotlin `CompiledModel`
    smoke. The OSS checkout needed temporary local `android_sdk_repository` and
    `android_ndk_repository` entries in `build/upstream-litert-main/WORKSPACE`.
    After that, Bazel analysis and Android actions start, but the build is
    blocked by Android toolchain friction rather than LiteRT runtime behavior:
    NDK r28/r26 fail because Bazel legacy Android crosstool injects missing
    `aarch64-linux-android-4.9` `-gcc-toolchain` paths; NDK r21 is supported but
    its clang cannot compile XNNPACK/KleidiAI ARMv8.2 `i8mm`/`bf16` assembly;
    NDK r22 passes the quick GCC-dir/clang-feature probe but then fails on
    Android sysroot header discovery; public `--define=tflite_with_xnnpack=false`
    flags still leave KleidiAI in the AAR dependency tree. The official
    `ci/build_maven_with_docker.sh` path was also tried and reached
    `//litert/kotlin:litert`, then stalled under amd64 Docker emulation on Apple
    Silicon at `@@litert_maven//:com_google_android_gms_play_services_basement`
    resource compilation (`4,444 / 4,485` actions) for about 40 minutes before
    being stopped; see
    `logs/litert-main-official-maven-build-retry-20260531T065120Z.log`.
    Rerun that AAR build on native x86_64 Linux if we need a coherent
    source-built Android/Kotlin smoke. The local smoke build now supports
    `LITERT_LOCAL_AAR=/path/to/litert.aar`, so a future successful source-built
    or published AAR can be tested without changing the Maven default.
  - Production conclusion: do not switch to LiteRT yet. LiteRT is usable for
    validation and the `main` C++ stack is technically promising, but the
    existing TFLite+QNN HTP Android app path remains the supported production
    runtime until a matched release-quality LiteRT Qualcomm provider package is
    available and passes the live V0b gate.

## Stop Condition

V0a is complete. V0b has verified QNN-required backend behavior, Depth Anything
asset loading, reusable Depth Anything preprocessing/inference, Depth Anything-sized
downsampling plus YOLO detection fusion into the 15x15 planner, a reusable
corridor pipeline, and a pure-Kotlin 3-frame command confirmation state
machine. QNN HTP transport is now operational on the current target-class
Snapdragon 8 Gen 2 phone after declaring the public vendor FastRPC native
library and using explicit app native-library paths for QNN. Both model smoke
tests pass on QNN HTP, and the live corridor path executes QNN depth frames.
The short V0b machine gate and 30-minute thermal gate now pass on the target
Snapdragon 8 Gen 2 phone: live Depth Anything runs above the 10 FPS target on
QNN HTP, severe frame-loss count is zero under the refined runtime safety
policy, normal corridor guidance is spoken, and low-confidence safe STOP is
proven on device. Emergency STOP behavior for near obstacles, severe runtime
frame loss, and low confidence is covered in unit tests and real-device
safe-stop proof. The known-corridor sighted-spotter proof remains the next V0b
proof before calling the full corridor demo complete.

## Next Agent-Owned Step

Keep the production Android runtime on the proven QNN path; use
`scripts/verify-v0b-device.sh` as the short machine gate and
`RUN_THERMAL_GATE=1 scripts/verify-v0b-device.sh` as the sustained Android
regression gate. The LiteRT validation has native accelerator evidence for Roana
YOLO/Depth AOT on SM8550, but the current LiteRT path is slower than the
existing TFLite+QNN path and the only running runtime stack still has QNN
version mismatch warnings. Testing `litert:2.1.5` is worthwhile only when a
matching Qualcomm LiteRT dispatch/runtime package is available; mixing 2.1.5
core with the public v2.1.1 dispatch/plugin is ABI-incompatible. Do not start a
live V0b LiteRT trial or production LiteRT migration until a matched
AOT/runtime path removes the warnings and matches or beats TFLite+QNN timing.
The next V0b proof is the known-corridor sighted-spotter run when a human can
perform it.
iOS S0 physical-device verification remains blocked until full Xcode is
installed. Do not add a lower-performance CPU fallback path.

For the corridor proof, run:

```bash
CORRIDOR_TEST_NOTES="known indoor corridor; blindfolded tester; sighted spotter; no intervention" \
  scripts/record-v0b-corridor-test.sh
```

## No-Touch Scope

- Do not start BLE, outdoor navigation, cloud/VLM, or custom training work in
  V0.
- Do not add CPU/XNNPACK fallback for the Snapdragon 8 Gen 2 path; QNN HTP
  transport and the short live V0b gate are now proven on the target phone.
