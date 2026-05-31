# Android LiteRT Validation Plan

> Plan for validating LiteRT `CompiledModel` as a more portable Android
> acceleration layer without replacing the current proven TFLite + Qualcomm QNN
> delegate production path prematurely.

**Status:** Phase 1 executed / Qualcomm JIT unavailable on SM8550; AOT
positive-control reached accelerator execution; source-built `main` C++ stack
passes Roana AOT smoke with matched QAIRT `2.46.0` /
2026-05-31.

**Implementation review note / 2026-05-30:** `intuitive-flow` reconciled the
plan-intake gate in place. Accepted execution decisions: keep this repo's
existing `docs/plan/` path as the canonical plan location for this run; start
with the preferred debug-only app path, but switch to the plan's isolated sample
module option if LiteRT conflicts with the proven QNN app classpath; pin
`com.google.ai.edge.litert:litert` to `2.1.5`; use the API shape
`Environment.create(BuiltinNpuAcceleratorProvider(context,
NpuCompatibilityChecker.Qualcomm))`, `CompiledModel.Options(Accelerator.NPU)`,
`CompiledModel.create(...)`, `createInputBuffers()`, `createOutputBuffers()`,
and `run(...)`; treat `Accelerator.NPU` alone as a request that LiteRT expands
internally to an NPU/CPU candidate set, so the verifier must only pass when
the app logs explicit requested/selected NPU evidence and must fail on
`selected=unavailable`, `status=missing`, `status=rejected`, or
`status=unproven`. No production runtime switch is accepted in Phase 1.

**Execution result / 2026-05-30:** Phase 1 produced
`logs/litert-smoke-20260530T122948Z.log` on Xiaomi `2211133C` / `fuxi` /
SM8550 / Android 16 / HyperOS OS3.0 with LiteRT `2.1.5`. YOLO and Depth
Anything both loaded and completed one timing iteration with NPU requested, but
both logged `litert_backend status=unproven` because `CompiledModel` does not
expose actual backend selection. The verifier failed by design with
`LiteRT backend proof unproven for model(s): yolo depth.` This triggers Stop
Condition 4, so Phase 2 QNN comparison and live V0b LiteRT trial are not
started.

**Runtime-matching follow-up / 2026-05-30:** A follow-up tried to make the
Qualcomm LiteRT path actually run, not just classify it as unproven. Packaging
`libLiteRtDispatch_Qualcomm.so` removed the earlier `No dispatch library found`
blocker, but `logs/litert-smoke-20260530T131348Z.log` still fell back to
XNNPACK after `Failed to initialize Dispatch API`. Rebuilding the smoke APK
with LiteRT `2.1.1` and a mixed runtime set showed the underlying mismatch more
clearly: `logs/litert-smoke-20260530T134350Z.log` reported
`Qnn System library version 1.10.0 is used. The version LiteRT using is 1.6.0.`
After replacing `libQnnHtp.so`, `libQnnSystem.so`, and
`libQnnHtpV73Stub.so` with the official sample V73 binaries, the version warning
disappeared, FastRPC created an unsigned CDSP user PD, and
`libQnnHtpV73Skel.so` opened, but `logs/litert-smoke-20260530T141116Z.log`
still failed at `Qnn failed to call device create, 1008`.

Adding the Qualcomm compiler plugin from the official MobileNet sample and
matching it with LiteRT `2.1.4` advanced an intermediate JIT path:
`logs/litert-smoke-20260530T142110Z.log` shows the plugin was loaded,
resolved, and initialized. It then failed because the packaged V73 runtime's
`libQnnSystem.so` is version `1.6.0`, while that compiler plugin requires at
least `1.8.0`. The MobileNet sample also ships a fuller Qualcomm runtime set
including `libQnnHtpPrepare.so`, but for V79, not this device's SM8550/V73
target.

The best matched JIT attempt used LiteRT `2.1.1`, the official
`litert_npu_runtime_libraries_jit.zip` V73 compiler/dispatch libraries, and
QAIRT `2.41.0.251128` V73 QNN libraries including `libQnnHtpPrepare.so`.
`logs/litert-smoke-20260530T144736Z.log` and
`logs/litert-smoke-20260530T145843Z.log` show Qualcomm dispatch initializing
with `Dispatch API vendor ID: Qualcomm` and QNN API build
`v2.41.0.251128145156_191518`; FastRPC creates an unsigned CDSP user PD and
opens `libQnnHtpV73Skel.so`. The JIT compiler still applies zero plugins:
`0 compiler plugins were applied successfully`, with
`failed to call device create, 14001`, followed by
`Created TensorFlow Lite XNNPACK delegate for CPU`. A default-provider control
run in `logs/litert-smoke-20260530T150158Z.log` reproduced the same `14001`,
so the explicit Qualcomm compatibility checker is not the cause.

The official EfficientDet-Lite0 TFLite positive-control model reproduced the
same failure. `logs/litert-smoke-20260530T153551Z.log` loaded EfficientDet,
initialized Qualcomm dispatch, opened `libQnnHtpV73Skel.so`, then failed at
`QnnDevice_create` with `14001`, applied zero compiler plugins, and created the
TFLite XNNPACK CPU delegate. A later instrumented run,
`logs/litert-smoke-20260530T155100Z.log`, proved the APK native directory
contained the expected V73 LiteRT/QNN libraries, successfully preloaded
`QnnSystem`, `QnnHtp`, `QnnHtpPrepare`, `QnnHtpV73Stub`,
`LiteRtDispatch_Qualcomm`, and `LiteRtCompilerPlugin_Qualcomm`, and enabled
Qualcomm DEBUG logging/profiling. It still produced
`QnnDevice_create` failure `14001`, with zero `QnnDevice_create done`, zero
`QnnContext_create`, zero `QnnGraph_execute`, and XNNPACK CPU fallback.

A same-session production QNN positive control,
`logs/qnn-smoke-20260530T155245Z.log`, passed with `QNN_VARIANT=explicit_paths`
on the same phone: `QnnDevice_create done` appeared twice,
`QnnGraph_execute` evidence appeared 136 times, and YOLO timing was `2.79 ms`.
`scripts/compare-litert-qnn-logs.py` classifies the delta as LiteRT Qualcomm JIT
device setup/runtime configuration, not a global device or production QNN
transport failure.

Current decision: LiteRT Next is not proven unusable globally, but the current
Roana SM8550/V73 Qualcomm JIT path is unavailable for product use. The logs now
prove Qualcomm runtime/dispatch reachability, then a QNN device-create failure
before graph compilation, followed by CPU fallback, while the existing
production QNN path can create devices and execute graphs in the same session.
Do not treat any LiteRT JIT timing from these runs as NPU timing. Remaining
high-value checks are an AOT/precompiled LiteRT Qualcomm sample/model path that
avoids on-device JIT, the official Qualcomm sample APK/model using Play Feature
Delivery-style runtime modules and strict NPU-required logging, or a
newer/more device-matched V73 runtime from Google/Qualcomm.

**Official-sample control / 2026-05-30:** The official EfficientDet Kotlin NPU
sample was built from `/tmp/litert-samples` after adding the same
`android.experimental.enableDeviceTargetingConfigApi=true` flag used by the
other LiteRT NPU samples. The AAB then packaged the V73 Qualcomm runtime module
with `libLiteRtDispatch_Qualcomm.so`, `libLiteRtCompilerPlugin_Qualcomm.so`,
`libQnnHtpPrepare.so`, and the V73 QNN libraries. MIUI blocked fresh
`com.example.*` installs with `INSTALL_FAILED_USER_RESTRICTED`, so the sample
was temporarily rebuilt with application id `com.roana.litertsmoke` and the V73
runtime copied into base `jniLibs`; the original smoke APK was reinstalled
after the run. The PID-filtered official-sample log
`logs/litert-official-efficientdet-pidfiltered-20260530T162507Z.log` proves why
sample UI/backend strings are insufficient: Java logs say
`Selected LiteRT backend=NPU`, but native logs say
`NPU accelerator could not be loaded and registered:
kLiteRtStatusErrorInvalidArgument`, then `Created TensorFlow Lite XNNPACK
delegate for CPU`. No Qualcomm dispatch, `QnnDevice_create`, or
`QnnGraph_execute` evidence appears in that PID-filtered run.

**Provider/options matrix / 2026-05-30:** The isolated smoke app now supports
`LITERT_NPU_PROVIDER=qualcomm|default|none` and
`LITERT_QUALCOMM_OPTIONS=full|minimal|none`. EfficientDet controls showed:
`logs/litert-smoke-20260530T163039Z.log` (`qualcomm/full`),
`logs/litert-smoke-20260530T163119Z.log` (`default/minimal`), and
`logs/litert-smoke-20260530T163158Z.log` (`default/none`) all reach Qualcomm
dispatch, create a FastRPC unsigned CDSP user PD, open `libQnnHtpV73Skel.so`,
then fail before graph compilation at `QnnDevice_create` error `14001` and
fall back to XNNPACK CPU. This rules out Roana model export, explicit Qualcomm
compatibility checker selection, and full debug/profiling Qualcomm options as
the primary blocker for the current JIT path. The remaining useful checks are
AOT/AI Pack/precompiled LiteRT Qualcomm models or a newer/device-matched V73
runtime/provider package.

**AOT follow-up / 2026-05-30:** A precompiled EfficientDet-Lite0 AOT artifact
for `Qualcomm_SM8550` was added to the smoke APK as
`efficientdet_lite0_detection_Qualcomm_SM8550.tflite`. Inspecting the APK asset
shows the expected `LiteRtStamp`, `Qualcomm`, `SM8550`, `DISPATCH_OP`, and
`qnn_partition_0` markers, so the file is a real LiteRT dispatch/context-binary
model rather than a plain CPU TFLite model. The AOT smoke with LiteRT Android
core `2.1.1`, the v2.1.1 Qualcomm dispatch/compiler-plugin libraries, and QAIRT
`2.41.0.251128` V73 QNN libraries reproduced a later failure point:
`logs/litert-smoke-20260530T174119Z.log` initializes Qualcomm dispatch, creates
an unsigned CDSP user PD, opens `libQnnHtpV73Skel.so`, logs
`Compiler plugin path is provided in the environment, but the model is
pre-compiled. Plugins won't be applied.`, finds `qnn_partition_0`, then fails
at `Failed to create QNN context: 5000`. It records zero `QnnContext_create`
success and zero `QnnGraph_execute`.

The AOT options matrix reproduced the same context failure with
`LITERT_QUALCOMM_OPTIONS=minimal`
(`logs/litert-smoke-20260530T174441Z.log`) and
`LITERT_QUALCOMM_OPTIONS=none` (`logs/litert-smoke-20260530T174520Z.log`), so
the full debug/profiling Qualcomm options are not the primary cause. A CPU
control (`logs/litert-smoke-20260530T173822Z.log`) also failed on
`DISPATCH_OP`, as expected for a dispatch-only AOT model, and must not be used
as a performance comparison. A same-session production QNN control,
`logs/qnn-smoke-20260530T163540Z.log`, created QNN contexts twice and executed
QNN graphs 140 times on the same phone, so the current evidence points to
LiteRT AOT context-binary/runtime compatibility rather than a global QNN device
or context failure.

The public stable Android LiteRT Maven artifact is currently `2.1.5`, while the
official AOT tutorial uses `ai-edge-litert-nightly` plus
`ai-edge-litert-sdk-qualcomm-nightly`. A local dry-run resolved both nightly
Python packages as `2.2.0.dev20260529`, but the Qualcomm AOT SDK reports that
Qualcomm AOT compilation is only supported on Linux x86 hosts. A macOS arm64
host cannot directly rebuild a matched Qualcomm AOT artifact. The next useful
LiteRT check is therefore either a Linux x86 AOT build using the nightly
Qualcomm SDK plus a matching Android runtime/provider package, or a
Google/Qualcomm-published AI Pack/sample that ships the compiled model and
runtime together. Until that path produces smoke-PID `QnnContext_create` and
`QnnGraph_execute` evidence, do not compare LiteRT timings or integrate LiteRT
into production.

**Nightly AOT control / 2026-05-31:** The Linux x86 AOT branch succeeded inside
Docker images `roana-litert-aot-sm8550:20260531` and
`roana-litert-aot-sm8550:20260531-libcxx` after installing
`ai-edge-litert-nightly==2.2.0.dev20260529`,
`ai-edge-litert-sdk-qualcomm-nightly==2.2.0.dev20260529`, and the host
`libc++`/`libunwind` packages needed by the SDK. The compiler required
`LD_LIBRARY_PATH` to point at the SDK's
`ai_edge_litert_sdk_qualcomm/data/lib/x86_64-linux-clang` directory and target
`qnn_target.Target(qnn_target.SocModel.SM8550)`.

The resulting artifact,
`build/litert-aot-sm8550/efficientdet_lite0_detection_Qualcomm_SM8550_apply_plugin.tflite`,
is 4.7 MB with SHA256
`fd211463599e07c431cd9713f7140124205b0a63601fd7488c264635db047466`. It contains
the expected `LiteRtStamp`, `Qualcomm`, `SM8550`, `DISPATCH_OP`, and
`qnn_partition_0` markers. Packaging that file as
`assets/efficientdet_lite0_detection_Qualcomm_SM8550.tflite` and rebuilding the
smoke APK with `LITERT_EXTRA_ASSET_DIR="$PWD/build/litert-aot-sm8550/assets"`
produced `logs/litert-smoke-20260531T012554Z.log`.

`logs/litert-smoke-20260531T012554Z.log` was the first positive LiteRT AOT
accelerator control on the target SM8550 phone: the smoke PID loaded the AOT
asset, initialized Qualcomm dispatch with QNN API `2.35.0`, found
`qnn_partition_0`, opened the V73 HTP skel, created an unsigned CDSP user PD,
emitted two smoke-PID `QNN accelerator (execute) time` profiling entries plus
RPC/cycle timing, and completed one EfficientDet timing iteration at `20.63 ms`.
A repeat run, `logs/litert-smoke-20260531T014103Z.log`, used five timing
iterations and emitted six smoke-PID QNN accelerator execute profiling entries
for one load run plus five timed runs; EfficientDet averaged `21.55 ms` with
`20.46 ms` min and `22.07 ms` max. The analyzer classifies both as
`aot_accelerator_execute_evidence_with_runtime_warnings`.

The same Docker AOT path then compiled the Roana models for SM8550:
`build/litert-aot-sm8550-roana/yolo/yolo11n-det-int8-smart_Qualcomm_SM8550_apply_plugin.tflite`
is 3.0 MB with SHA256
`9bbbc250e79128d7c502fef81a81b45d73b6c6ce92b5e854a096ddd44d2ae11d`; the
compiler reported `316 / 316 ops offloaded to 1 partitions`.
`build/litert-aot-sm8550-roana/depth/depth_anything_v2_Qualcomm_SM8550_apply_plugin.tflite`
is 50 MB with SHA256
`30ba9e1b057dfd38eb4fe41b4c7e28dd66ffc72a21b378219a97d2f95016540d`; the
compiler reported `598 / 598 ops offloaded to 1 partitions`. The packaged smoke
assets are under `build/litert-aot-sm8550-roana/assets/`, and the process is now
scripted by `scripts/compile-litert-qualcomm-aot.sh`.

`logs/litert-smoke-20260531T022907Z.log` ran those Roana AOT assets on the
SM8550 phone with `MODEL=all_aot`, `LITERT_VERSION=2.1.1`, Qualcomm NPU
provider, full Qualcomm options, and five timing iterations. The analyzer
classifies it as `aot_accelerator_execute_evidence_with_runtime_warnings`: the
smoke PID initialized Qualcomm dispatch with QNN API `2.35.0`, found a QNN
graph, opened the V73 HTP skel, created an unsigned CDSP user PD, and emitted
12 smoke-PID `QNN accelerator (execute) time` entries plus RPC/cycle timing.
Roana LiteRT AOT timing was:

- YOLO AOT: `13.60 ms` average (`13.26 ms` min, `14.11 ms` max), load
  `785.28 ms`.
- Depth AOT: `87.53 ms` average (`87.17 ms` min, `87.93 ms` max), load
  `213.92 ms`.

Fresh same-phone TFLite+QNN controls show the current production path is still
faster:

- `logs/qnn-smoke-20260531T023528Z.log`: YOLO explicit-path QNN averaged
  `3.74 ms` across five iterations. The earlier full-log QNN control
  `logs/qnn-smoke-20260530T155245Z.log` averaged `2.79 ms` and contains native
  graph-execution evidence.
- `logs/qnn-smoke-20260531T023627Z.log`: Depth explicit-path QNN averaged
  `52.75 ms` across five iterations. The earlier full-log QNN control
  `logs/qnn-smoke-20260530T002450Z.log` averaged `53.47 ms` and contains native
  graph-execution evidence.

Current performance decision: LiteRT AOT is usable as a validation/spike path
on this phone, but not as a production replacement. On the current evidence it
is about `3.64x` slower than TFLite+QNN for YOLO using the fresh isolated
control, and about `1.66x` slower for Depth. Against the earlier best YOLO QNN
control (`2.79 ms`), YOLO AOT is about `4.87x` slower.

The runtime mismatch warning remains unresolved. The successful Roana AOT run
still reports `QnnSystem 1.10.0` vs LiteRT `1.6.0`, QNN API `2.35.0` vs LiteRT
`2.31.0`, and backend `5.46.0` vs LiteRT `5.41.0`; it also contains an XNNPACK
CPU delegate creation line and lacks smoke-PID `QnnGraph_execute done status
0x0`. A controlled rebuild with the older v2.1.1/QAIRT `2.41.0.251128` V73
runtime removed the mismatch (`qnn_runtime_mismatch=false`) but failed both
Roana AOT models at `Failed to create QNN context: 5000`
(`logs/litert-smoke-20260531T025130Z.log`). Public metadata checked during the
run still shows stable Android Maven `com.google.ai.edge.litert:litert` latest
`2.1.5`, while GitHub `v2.1.5` only publishes `litert_cc_sdk.zip`; the public
Qualcomm Android runtime zip remains available only on `v2.1.1`. A matched
Android Qualcomm dispatch/runtime bundle for the nightly QNN `2.35`/backend
`5.46` stack is still missing.

**Version/path research / 2026-05-31:** A follow-up checked whether the newer
LiteRT release is actually worse, or whether the supported packaging path moved.
The answer is the latter: the public `2.1.5` Java/C++ APIs still expose NPU and
Qualcomm options, but the public stable release does not publish a matching
Android Qualcomm dispatch/plugin bundle. `logs/litert-smoke-20260531T031238Z.log`
rebuilt the Roana AOT smoke with `LITERT_VERSION=2.1.5` while keeping the public
v2.1.1 Qualcomm dispatch/plugin libraries; it failed before model execution
because `libLiteRtDispatch_Qualcomm.so` cannot resolve
`LiteRtQualcommOptionsGet`. Symbol inspection confirms the ABI shift:
`litert:2.1.1` `libLiteRt.so` exports `LiteRtQualcommOptionsGet*`, while
`litert:2.1.5` no longer exports those old symbols and the C/C++ SDK uses the
newer `LrtQualcommOptions*` API.

Replacing only the QNN runtime with the latest public Qualcomm Maven
`com.qualcomm.qti:qnn-runtime:2.46.0` does not fix this, because the missing
symbol is between LiteRT core and the Qualcomm dispatch/plugin, not between
dispatch and QNN. `logs/litert-smoke-20260531T032120Z.log` packaged
`litert:2.1.5`, the old v2.1.1 dispatch/plugin, and Maven `qnn-runtime:2.46.0`;
it failed at the same `LiteRtQualcommOptionsGet` load error. The companion
`com.qualcomm.qti:qnn-litert-delegate:2.46.0` AAR contains
`libQnnTFLiteDelegate.so` and `libqnn_delegate_jni.so`, so it maps to the
traditional TFLite/QNN delegate path rather than the LiteRT `CompiledModel`
dispatch provider path.

Official samples and docs point to the correct newer packaging shape:
`CompiledModel` plus AOT/JIT, AI Pack / Play delivery for models, and dynamic
feature or base APK delivery for native NPU runtime libraries. AI Pack itself is
not a native-library delivery mechanism. The checked Google samples still keep
Qualcomm NPU examples on `litert=2.1.0` or `2.1.1`, and the C++ prebuilt NPU
sample explicitly documents `litert:2.1.1` plus
`libLiteRtDispatch_Qualcomm.so` from the v2.1.1 NPU runtime zip. C++ therefore
does not bypass the blocker: the 2.1.5 C++ SDK has the newer Qualcomm option
API, but it still needs a matching `libLiteRtDispatch_Qualcomm.so`, which is not
present in the public v2.1.5 release assets.

GitHub issue/PR cross-check, 2026-05-31:

- `google-ai-edge/LiteRT#6889` asks Google to publish a prebuilt
  `libLiteRtDispatch_Qualcomm.so` compatible with each Android AAR release. The
  reporter independently found dispatch ABI mismatch when building provider libs
  from a different LiteRT commit, then fixed that part by rebuilding from the
  AAR-matched commit.
- `google-ai-edge/LiteRT#5592` and `google-ai-edge/LiteRT#5594` show other
  developers hitting the same class of Qualcomm `CompiledModel` failures:
  missing compiler/dispatch discovery, `No usable Dispatch runtime found`, and
  dispatch API mismatch on Snapdragon 8 Gen 2/3/Elite devices. Workarounds in
  those threads include physical native library extraction, correct
  `libQnnHtpPrepare.so`, and `libcdsprpc.so` manifest visibility. Roana already
  covers these discovery/linker fixes in the smoke app and gets past them in the
  passing 2.1.1 AOT run.
- `google-ai-edge/LiteRT-LM#2079`, `#2020`, and `#2226` show the same failure
  family on LiteRT-LM: native library directory wiring, `libcdsprpc.so`
  visibility, `LiteRtQualcommOptionsGet`, and QNN system-version mismatch.
- `google-ai-edge/LiteRT` main is still active. On 2026-05-30 UTC it had fresh
  merges for Samsung/MediaTek/general runtime work, while current Qualcomm source
  uses the newer `LrtQualcommOptions*` / TOML opaque-options path and pins QAIRT
  `2.46.0.260424` in `third_party/qairt/workspace.bzl`. Open Qualcomm PRs such
  as `#7612`, `#7517`, `#7576`, and `#5769` show the backend is active, not
  removed. The unresolved public-consumption issue is matching Android provider
  artifact availability.

Adjacent Google AI Edge stack check, 2026-05-31:

- **MediaPipe:** worth monitoring for pipeline structure, but not a near-term
  replacement for Roana's current Android inference backend. Google's Edge
  overview frames MediaPipe Framework as a way to build multi-model
  preprocessing/inference/postprocessing pipelines, while LiteRT remains the
  hardware-specific model runtime. Roana already owns a small Kotlin pipeline
  with proven QNN HTP timings; moving it to MediaPipe would add graph/calculator
  integration work without removing the Qualcomm LiteRT provider/version issue.
- **LiteRT-LM:** worth tracking for future on-device LLM features, not for the
  current YOLO + Depth Anything corridor loop. Official docs target `.litertlm`
  Gemma-family models and require SoC-specific `.litertlm` artifacts plus
  Qualcomm dispatch/QNN runtime libraries. Its public issues show the same
  native-library, `libcdsprpc.so`, dispatch ABI, and QNN-version concerns seen in
  plain LiteRT.
- **Main branch:** worth a bounded smoke spike only as a single-version
  source-built stack. That spike now passes: LiteRT `main` at
  `2efe1c141bc6598f7dcae973c989b1bcba71fc11` was built for Android arm64 with
  Qualcomm enabled, producing `run_model`, `libLiteRt.so`,
  `libLiteRtDispatch_Qualcomm.so`, and `libLiteRtCompilerPlugin_Qualcomm.so`.
  Packaged with QAIRT `2.46.0.260424` V73 libraries and the Roana AOT models,
  it ran on the SM8550 phone from `/data/local/tmp/litert-main-2efe1c1-qairt246`.
  `logs/litert-main-run-model-yolo-20260531T051859Z.log` and
  `logs/litert-main-run-model-depth-20260531T051911Z.log` both show
  `Context binary SDK version matches current SDK: 2.46.0`,
  `QnnDevice_create done`, `QnnContext_createFromBinary done successfully`,
  five `QnnGraph_execute done. status 0x0` entries, and five
  `QNN (execute) time` entries. C++ `run_model` averaged `3.106 ms` for YOLO
  and `47.977 ms` for Depth across five iterations. This proves the newer
  source stack can run; it is still not a production candidate until the same
  result is reproducible from a tagged release or published Maven/GitHub
  Android provider artifact set. Mixing `main` provider binaries with stable
  Maven `2.1.5` or with the v2.1.1 runtime zip remains an invalid test.
- **Main AAR follow-up:** also attempted the upstream `//litert/kotlin:litert`
  AAR target so the smoke APK could use a coherent source-built Java/Kotlin
  `CompiledModel` stack. The target requires explicit local
  `android_sdk_repository` / `android_ndk_repository` entries in OSS. With those
  added, the build reaches Bazel analysis and Android actions, but does not
  complete under the tested Docker toolchains: NDK r28/r26 are too new for
  Bazel's legacy `android_ndk_repository` crosstool and fail on injected
  `-gcc-toolchain` paths; NDK r21 is supported by Bazel but too old for
  XNNPACK/KleidiAI ARMv8.2 `i8mm`/`bf16` assembly flags; NDK r22 has both the
  old GCC directory and newer clang support but fails later on Android sysroot
  header discovery. Disabling TFLite/XNNPACK public defines was insufficient
  because the AAR dependency tree still compiles KleidiAI. This is an OSS Bazel
  Android packaging/toolchain blocker, not runtime evidence against `main`.
  The official `ci/build_maven_with_docker.sh` path was also tried with
  `BUILD_LITERT_KOTLIN_API=true`, `USE_LOCAL_TF=false`, and
  `--define=public_maven_build=true`. It reached `//litert/kotlin:litert`
  analysis and Android actions, then stalled on
  `@@litert_maven//:com_google_android_gms_play_services_basement` resource
  compilation at `4,444 / 4,485` actions for about 40 minutes under amd64 Docker
  emulation on Apple Silicon; the container was stopped and recorded in
  `logs/litert-main-official-maven-build-retry-20260531T065120Z.log`. That is a
  local build-environment limitation; rerun the AAR build on native x86_64 Linux
  before drawing conclusions about the upstream Android package. The smoke build
  now has a `LITERT_LOCAL_AAR` escape hatch for a future successful
  upstream/local AAR.

Production conclusion: keep Android production on the existing TFLite+QNN HTP
path. LiteRT AOT has native accelerator evidence for Roana YOLO/Depth on SM8550,
and `main` removes the earlier QAIRT mismatch when tested as a same-source C++
bundle. It is still not ready to replace production because the passing path is
not available as a stable Android Maven/release provider bundle, and the current
app integration uses the older `2.1.1`/nightly packaging shape. Do not run a
live V0b LiteRT trial or migration until a matched Qualcomm dispatch/runtime
package for a tagged/newer LiteRT release is available and the Android app path
meets or beats TFLite+QNN timing.

---

## 1. Objective

Validate whether LiteRT `CompiledModel` should become Roana's next Android
acceleration direction for broader device support.

The validation must answer:

1. Can the existing YOLO and Depth Anything `.tflite` assets load through
   LiteRT `CompiledModel`?
2. Can the current Snapdragon 8 Gen 2 phone run those models with NPU requested
   and without silent CPU fallback?
3. Can the result be proven with logs, timings, and failure semantics as clearly
   as the current QNN smoke gate?
4. Is LiteRT materially more portable for future Qualcomm, MediaTek, and Google
   Tensor devices than the current vendor-specific QNN delegate path?
5. If it works, what is the smallest migration shape that preserves the passing
   V0b Android gate?

---

## 2. Current Baseline

Production Android inference is currently:

- TFLite `Interpreter`;
- Qualcomm QNN LiteRT delegate;
- explicit QNN HTP backend options;
- no CPU/XNNPACK runtime fallback.

Known passing baseline:

- QNN smoke: `logs/qnn-smoke-20260530T045117Z.log`;
- short V0b machine gate: `logs/v0a-device-20260530T044604Z.log`;
- prior 30-minute thermal proof: `logs/v0a-device-20260530T024149Z.log`.

This path remains the production runtime until LiteRT has stronger evidence.

---

## 3. Why LiteRT Is Worth Validating

LiteRT `CompiledModel` is the current Google-directed Android API for
high-performance inference across CPU/GPU/NPU. The Android docs position
`CompiledModel` as the modern API and keep the old `Interpreter` API mainly for
compatibility. The NPU docs describe LiteRT as a unified NPU interface across
Google Tensor, Qualcomm AI Engine Direct, MediaTek NeuroPilot, and other
vendors.

That matches Roana's portability goal better than directly owning one
Qualcomm-specific delegate path forever.

Important caveat: LiteRT NPU deployment can involve AOT or on-device
compilation, Play for On-device AI / Play Feature Delivery, and vendor runtime
libraries. The current Xiaomi China ROM / sideloaded debug workflow may not be
able to use every Play-delivered path. The first validation must prove a
debug-sideloadable route before assuming LiteRT is product-ready.

---

## 4. Non-Goals

Do not do these during the validation slice:

- do not replace the production `InferenceBackend`;
- do not reintroduce CPU fallback;
- do not change corridor planner, TTS, or safety behavior;
- do not port to ONNX Runtime, ExecuTorch, or Qualcomm AI Hub context binaries;
- do not require Google Play distribution for the first smoke gate;
- do not optimize preprocessing while testing LiteRT model execution.

---

## 5. Success Criteria

LiteRT is a credible next runtime only if all of these are true:

1. `scripts/build-debug.sh` still builds the debug APK.
2. A new LiteRT smoke verifier produces one artifact under `logs/`.
3. YOLO loads and runs with `Accelerator.NPU` requested, or fails explicitly
   with a classified reason.
4. Depth Anything loads and runs with `Accelerator.NPU` requested, or fails
   explicitly with a classified reason.
5. The verifier can distinguish at least these outcomes:
   - `litert_backend selected=npu`;
   - `litert_backend selected=unavailable`;
   - `litert_model status=rejected`;
   - `litert_runtime status=missing`;
   - `litert_backend status=unproven`.
6. There is no path where LiteRT silently falls back to CPU and the verifier
   still passes.
7. Smoke timing is compared against the current QNN baseline.

Migration to production requires more:

- both YOLO and Depth pass LiteRT smoke;
- the live V0b short gate passes with LiteRT behind a debug-only switch;
- the current TFLite + QNN path remains available during comparison;
- at least one non-Snapdragon target or a credible documented device-coverage
  proof demonstrates portability value.

---

## 6. Phase 0: API And Dependency Probe

Goal: prove the current repo can add LiteRT without disturbing the passing QNN
runtime.

Tasks:

1. Re-run the metadata probe:

   ```bash
   python3 scripts/probe-android-acceleration-libs.py \
     --output logs/android-acceleration-libs-$(date -u +%Y%m%dT%H%M%SZ).json
   ```

2. Pin the LiteRT artifact version from the probe result. The last known probe
   found `com.google.ai.edge.litert:litert` latest `2.1.5`.
3. Inspect the official Kotlin sample API shape for `CompiledModel`,
   `Accelerator.NPU`, input/output buffers, and error reporting.
4. Decide whether the first implementation lives in:
   - a debug-only app path; or
   - a small isolated Android sample module.

Preferred choice: debug-only app path, because it reuses the current packaged
assets, ADB verifier scripts, and phone setup.

Acceptance:

- one short note in this plan or active status records the chosen LiteRT
  dependency version and API shape;
- no production runtime code is modified;
- Docker Android unit tests still pass after adding only the dependency if we
  add it in this phase.

---

## 7. Phase 1: LiteRT Model Smoke

Goal: add a standalone debug smoke path equivalent to `QnnModelSmoke`, but using
LiteRT `CompiledModel`.

Implementation shape:

- Add `LiteRtModelSmoke` under `app/src/main/java/com/roana/app/`.
- Gate it behind debug intent extras:
  - `com.roana.app.extra.DEBUG_LITERT_YOLO_SMOKE`;
  - `com.roana.app.extra.DEBUG_LITERT_DEPTH_SMOKE`;
  - `com.roana.app.extra.DEBUG_LITERT_ACCELERATOR`;
  - `com.roana.app.extra.DEBUG_LITERT_TIMING_ITERATIONS`.
- Add `scripts/verify-litert-smoke-device.sh`.
- Keep `QnnModelSmoke` unchanged.

Smoke behavior:

1. Load the same `.tflite` assets:
   - `yolo11n-det-int8-smart.tflite`;
   - `depth_anything_v2.tflite`.
2. Create `CompiledModel` with `Accelerator.NPU` requested first.
3. Allocate input/output buffers with LiteRT APIs.
4. Run zero-input timing iterations.
5. Log model metadata, backend request, backend result, load/compile time, run
   time, and failure reason.

Required log shape:

```text
litert_model_smoke_matrix accelerator=npu yolo=true depth=true timing_iterations=...
litert_model_metadata model=yolo ...
litert_backend requested=npu model=yolo
litert_model_smoke status=loaded model=yolo backend=npu load_ms=...
litert_model_timing status=ok model=yolo backend=npu avg_ms=...
```

If NPU cannot be proven:

```text
litert_model_smoke status=failed model=... backend=unproven reason=...
```

Acceptance:

- verifier passes only when requested models produce loaded/timing evidence with
  NPU proven;
- verifier fails on missing runtime libraries, model rejection, or unproven
  backend;
- no CPU fallback is accepted as a pass condition.

---

## 8. Phase 2: Compare Against Current QNN

Goal: decide whether LiteRT changes the runtime decision.

Run on the same phone and same APK build:

```bash
BUILD_FIRST=0 INSTALL_FIRST=0 MODEL=all QNN_VARIANT=explicit_paths \
  QNN_TIMING_ITERATIONS=5 LOG_SECONDS=60 scripts/verify-qnn-smoke-device.sh

BUILD_FIRST=0 INSTALL_FIRST=0 MODEL=all LITERT_ACCELERATOR=npu \
  LITERT_TIMING_ITERATIONS=5 LOG_SECONDS=60 scripts/verify-litert-smoke-device.sh
```

Compare:

- startup / compile / load time;
- steady-state YOLO run time;
- steady-state Depth run time;
- log evidence for actual NPU execution;
- native library footprint;
- failure mode when NPU is unavailable.

Acceptance:

- LiteRT is not considered better merely because it runs.
- LiteRT must either:
  - provide clearer portability with comparable performance; or
  - solve a concrete device/backend gap that current QNN cannot.

---

## 9. Phase 3: Debug-Only Live V0b Trial

Only start this after Phase 1 and Phase 2 pass.

Goal: prove LiteRT can survive the real CameraX live pipeline, not just a
zero-input smoke.

Implementation shape:

- add a debug-only backend selector, for example
  `EXTRA_DEBUG_INFERENCE_BACKEND=litert`;
- keep default production backend as current TFLite + QNN;
- start with Depth Anything first, because it is the V0b FPS bottleneck and has
  simpler output handling than YOLO's multi-output decode;
- only add YOLO after Depth proves stable.

Gate:

```bash
REQUIRE_THERMAL_MINUTES=0 REQUIRE_CORRIDOR_TEST=1 \
  DEBUG_INFERENCE_BACKEND=litert BUILD_FIRST=0 scripts/verify-v0b-device.sh
```

Acceptance:

- `litert_backend selected=npu` appears for the model under test;
- `corridor_live status=ok` appears;
- `depth_fps >= 10`;
- `gap_count == 0`;
- normal guidance feedback and low-confidence STOP proof still appear;
- result may remain `blocked` only for the known-corridor human proof.

---

## 10. Phase 4: Migration Decision

After the live debug trial, choose one:

### Keep Current QNN Path

Choose this if LiteRT:

- cannot prove NPU execution;
- depends on Play delivery unavailable to our sideload test path;
- is slower or less stable than current QNN on SM8550;
- only works on the same Qualcomm path without broader-device evidence.

### Keep Current QNN And Park LiteRT

Choose this if LiteRT smoke works but live V0b is not yet better. Record the
artifact and revisit when we have a MediaTek / Google Tensor phone.

### Migrate Behind A Runtime Interface

Choose this only if LiteRT:

- passes both smoke models;
- passes live V0b short gate;
- has no silent CPU fallback;
- has comparable or better performance;
- provides credible multi-vendor portability.

The migration should introduce a small explicit runtime interface, not a hidden
fallback chain:

```text
AndroidInferenceRuntime
  - QnnTfliteRuntime
  - LiteRtCompiledRuntime
```

Runtime selection must be explicit through build/debug configuration until
multi-device evidence is strong enough to change the default.

---

## 11. Risks And Watch Points

- LiteRT `CompiledModel` may conflict with the current `tensorflow-lite` /
  QNN-delegate dependency set.
- NPU runtime library delivery may assume Google Play / PODAI, while current
  testing uses direct ADB sideload on a China ROM phone.
- On-device JIT compilation may have a high first-run cost, especially for
  Depth Anything.
- AOT compilation may improve load time but introduces SoC targeting and Play AI
  Pack delivery complexity.
- If the API cannot expose or prove the actual accelerator used, performance
  alone is not enough evidence to migrate.
- Current QNN path is already fast enough for V0b, so LiteRT must justify itself
  through portability, maintainability, or clear failure-mode improvements.

---

## 12. Stop Conditions

Stop and report after the first true condition:

1. LiteRT dependency/API cannot compile in the repo.
2. LiteRT cannot run YOLO smoke with NPU requested.
3. LiteRT can run YOLO but cannot run Depth Anything.
4. LiteRT smoke passes both models but backend proof is unproven.
5. LiteRT native logs show Qualcomm JIT device setup failure plus CPU fallback;
   stop the JIT path and move only to AOT/AI Pack or newer runtime checks.
6. LiteRT AOT reaches accelerator execute profiling only for a positive-control
   model; record it, but do not proceed to Roana timing comparison until
   YOLO/Depth have their own native proof and runtime mismatch warnings are gone.
7. LiteRT smoke passes both Roana models with NPU proof; proceed to Phase 2 compare.
8. LiteRT live debug trial passes the short V0b gate; prepare a migration
   decision note.

At each stop, update `docs/status/active/v0-implementation.md` with:

- artifact path;
- device;
- LiteRT version;
- model result;
- backend proof status;
- decision.

---

## 13. Sources

- LiteRT for Android: <https://ai.google.dev/edge/litert/android>
- LiteRT NPU acceleration: <https://ai.google.dev/edge/litert/next/npu>
- Android LiteRT overview: <https://developer.android.com/ai/custom>
