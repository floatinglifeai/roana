# Android LiteRT Validation Plan

> Plan for validating LiteRT `CompiledModel` as a more portable Android
> acceleration layer without replacing the current proven TFLite + Qualcomm QNN
> delegate production path prematurely.

**Status:** proposed validation plan / 2026-05-30.

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
5. LiteRT smoke passes both models with NPU proof; proceed to Phase 2 compare.
6. LiteRT live debug trial passes the short V0b gate; prepare a migration
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
