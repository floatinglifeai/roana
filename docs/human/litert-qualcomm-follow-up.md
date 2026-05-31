# LiteRT Qualcomm Follow-Up

This note captures where Roana left the LiteRT + Qualcomm NPU investigation on
2026-05-31, so we can pause it without losing the decision context.

## Summary

Do not switch Roana's production Android runtime to LiteRT yet.

The existing TFLite + QNN HTP path remains the supported production runtime.
LiteRT is promising, and the newest source-built C++ stack proved that Roana's
YOLO and Depth models can run on the SM8550 NPU with good performance, but the
Android app integration path is not release-ready because the public Android
LiteRT AAR and Qualcomm dispatch/runtime provider packages are not yet available
as one matched, production-friendly bundle.

## What We Proved

### AOT compilation works

The Linux x86 Docker path successfully compiled Qualcomm SM8550 AOT models with
`ai-edge-litert-nightly==2.2.0.dev20260529` and
`ai-edge-litert-sdk-qualcomm-nightly==2.2.0.dev20260529`.

Artifacts:

- EfficientDet AOT model under `build/litert-aot-sm8550/`
- Roana YOLO AOT model under `build/litert-aot-sm8550-roana/yolo/`
- Roana Depth AOT model under `build/litert-aot-sm8550-roana/depth/`

The Roana AOT compile offloaded all model ops:

- YOLO: `316 / 316` ops
- Depth: `598 / 598` ops

### Android LiteRT AOT can execute on NPU

The smoke APK run in `logs/litert-smoke-20260531T022907Z.log` loaded the Roana
AOT models, initialized Qualcomm dispatch, found a QNN graph, opened the V73 HTP
skel, created a FastRPC user PD, and emitted QNN accelerator execute profiling.

Measured smoke timings:

| Runtime | YOLO | Depth |
| --- | ---: | ---: |
| LiteRT AOT in Android smoke APK | `13.60 ms` | `87.53 ms` |
| Current TFLite + QNN explicit paths | `3.74 ms` | `52.75 ms` |

This proves an Android LiteRT AOT path can reach the NPU, but it is slower than
the current production QNN path and still carries runtime warnings. Treat this
as positive validation evidence, not a migration proof.

### Source-built LiteRT main performs well

We built LiteRT `main` at commit `2efe1c141bc6598f7dcae973c989b1bcba71fc11`
for Android arm64 with Qualcomm support and QAIRT `2.46.0.260424`.

Device logs:

- `logs/litert-main-run-model-yolo-20260531T051859Z.log`
- `logs/litert-main-run-model-depth-20260531T051911Z.log`

The native `run_model --accelerator=npu` path produced the evidence we wanted:

- `Context binary SDK version matches current SDK: 2.46.0`
- `QnnDevice_create done`
- `QnnContext_createFromBinary done successfully`
- repeated `QnnGraph_execute done. status 0x0`

Measured native timings:

| Runtime | YOLO | Depth |
| --- | ---: | ---: |
| LiteRT main C++ `run_model` | `3.106 ms` | `47.977 ms` |
| Current TFLite + QNN explicit paths | `3.74 ms` | `52.75 ms` |

This removes the main performance concern. The newer LiteRT source stack can run
Roana models on SM8550 NPU at production-relevant speed.

## Why We Are Pausing

The remaining blocker is Android product integration, not model performance.

The good C++ result was produced by a hand-built native bundle pushed to the
device and run through `run_model`. The production app needs a maintainable
Android integration shape: Kotlin/Java APIs or a deliberate JNI layer, stable
native library packaging, matched model/runtime versions, lifecycle handling,
crash/debug support, and a rollback path.

The standard Android/Kotlin path is currently blocked by packaging mismatch:

- Public `com.google.ai.edge.litert:litert` reached `2.1.5`.
- Public Qualcomm LiteRT dispatch/plugin Android libraries still match the
  older `2.1.1` ABI.
- Mixing those generations fails before model execution.
- Building a coherent source-built LiteRT AAR locally hit Android/Bazel/NDK
  toolchain friction, and the official Docker Maven build stalled under amd64
  emulation on Apple Silicon.

## Next Time We Revisit

Start from one of these two paths:

1. Check whether Google/Qualcomm have published a matched Android LiteRT AAR and
   Qualcomm dispatch/runtime provider package. If yes, test it through the
   existing `litert-smoke` module using `LITERT_LOCAL_AAR` or Maven dependency
   updates.
2. If waiting for a release is not acceptable, build a feature-flagged native
   JNI prototype from the successful C++ `run_model` stack and connect it to the
   app's inference abstraction. This is viable, but it means Roana owns the JNI,
   tensor marshaling, native crash handling, and runtime packaging surface.

Until one of those paths is complete, keep production inference on TFLite + QNN
HTP.

