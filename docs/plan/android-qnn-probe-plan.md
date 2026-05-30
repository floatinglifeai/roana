# Android QNN Probe Plan

> Focused diagnosis plan for the Snapdragon 8 Gen 2 performance blocker found
> during V0b testing. This plan decides which Android acceleration options are
> worth trying now, and which should wait until the QNN transport failure is
> better understood.

**Status:** QNN transport solved; alternative backend probes tracked /
2026-05-30.

---

## 1. Current Finding

The current Xiaomi target-class phone originally looked slow because QNN HTP
transport failed before either model could prove operator compatibility:

- Device: Xiaomi `2211133C`, `SM8550`, board `kalama`, Android 16 / HyperOS
  `OS3.0.307.0.WMCCNXM`.
- Key artifact: `logs/qnn-smoke-full-20260529T154349Z.log`.
- Failure markers:
  - `QnnDsp loadRemoteSymbols failed with err 4000`;
  - `Failed to create transport for device`;
  - `Failed to load skel`;
  - `Transport layer setup failed: 14001`.

That root cause is now resolved for the existing TFLite/QNN delegate path:
declaring the optional vendor FastRPC library (`libcdsprpc.so`) made the
transport visible to the app linker namespace. The current target phone now
passes QNN smoke, the short V0b machine gate, and the 30-minute thermal gate on
QNN HTP.

Current decision: keep the passing QNN HTP delegate path as the production
Android path while tracking other Android speedup libraries as non-disruptive
spikes.

Cleanup evidence from 2026-05-30: production Android inference now has no
CPU/XNNPACK runtime fallback. `InferenceBackend` requires a QNN delegate,
YOLO/Depth interpreter creation failures log `selected=unavailable` and fail,
and `scripts/verify-v0a-device.sh` rejects unavailable backend logs. The only
remaining XNNPACK interpreter is the QNN smoke's metadata-only tensor summary,
guarded by `InferenceBackendPolicyTest`.

---

## 2. Decision

Do **not** implement every acceleration option now, and do not replace the
passing QNN HTP delegate path without a measured reason.

Run lightweight metadata/probe gates first, then decide whether to invest in a
heavier runtime spike. CPU fallback is no longer a production runtime path; if
a target device fails the current QNN HTP path, treat it as a backend support
gap to diagnose or route to another accelerated runtime spike.

---

## 3. Ranked Options

| Rank | Option | Try now? | Why |
|---|---:|---|---|
| 1 | Current TFLite + QNN delegate | Keep | Proven on SM8550 with QNN smoke, short V0b, and 30-minute thermal gates. |
| 2 | LiteRT `CompiledModel` / LiteRT Next metadata probe | Track now | Strategic portable layer for Qualcomm + MediaTek; start with artifact/API availability, not a runtime switch. |
| 3 | ONNX Runtime QNN cross-check | Diagnostic only | Good for proving whether a future QNN regression is below TFLite; not the product runtime choice. |
| 4 | Qualcomm AI Hub context binary | Later | Useful flagship fast path if first-run compile or per-SoC squeezing becomes important. |
| 5 | ExecuTorch QNN | Defer | Real backend exists, but migration to `.pte` and PyTorch mobile flow is too heavy while QNN HTP already passes. |
| 7 | CPU fallback runtime | Removed | Silent CPU fallback hides real QNN/NPU failures and cannot satisfy V0b performance gates. |

## 4. Phase 0: Alternative Library Metadata Probe

Run:

```bash
python3 scripts/probe-android-acceleration-libs.py \
  --output logs/android-acceleration-libs-$(date -u +%Y%m%dT%H%M%SZ).json
```

The probe currently checks official Maven metadata for:

- `com.google.ai.edge.litert:litert`;
- `com.microsoft.onnxruntime:onnxruntime-android`;
- `com.microsoft.onnxruntime:onnxruntime-android-qnn`;
- `org.pytorch:executorch-android`.

Acceptance:

- The script returns JSON with `status=passed`.
- Candidate latest versions are visible in the artifact.
- The decision remains non-invasive: keep the passing QNN HTP runtime and only
  start a LiteRT spike if we need broader device coverage or a measured reason
  to migrate.

---

## 5. Phase 1: True-Device QNN Probe

Add or extend a script that runs quickly on the connected Android phone and
produces a single log artifact.

Suggested script:

```bash
scripts/probe-qnn-device.sh
```

The probe should collect:

1. Device identity:
   - `ro.product.manufacturer`;
   - `ro.product.model`;
   - `ro.board.platform`;
   - `ro.soc.model`;
   - Android SDK and build fingerprint.
2. APK and install layout:
   - package path from `pm path com.roana.app`;
   - app data/native library locations if visible;
   - ABI list from `ro.product.cpu.abilist`.
3. Packaged QNN artifacts:
   - app-side `libQnn*.so`;
   - TFLite QNN delegate library;
   - HTP stub/skel artifacts;
   - any architecture-specific subdirectories.
4. Device-visible vendor/system QNN hints:
   - relevant `/vendor/lib64`, `/system_ext/lib64`, or linker-visible QNN /
     Hexagon / DSP libraries when accessible without root;
   - SELinux denials or linker errors in logcat during the smoke run.
5. Smoke result:
   - run `scripts/verify-qnn-smoke-device.sh`;
   - preserve full logcat around the delegate creation attempt;
   - classify as transport failure, model rejection, or unknown.

Acceptance:

- Probe completes in under 2 minutes.
- Output artifact is written under `logs/`.
- The artifact contains enough detail to decide whether to try delegate options
  or jump to LiteRT Next.

---

## 6. Phase 2: Minimal QNN Delegate Option Spike

Only start this phase after Phase 1 confirms that packaged artifacts and runtime
paths are plausible or identifies a specific missing path to override.

Try one variable at a time:

1. Explicit QNN library path, if the delegate exposes it.
2. Explicit HTP skel/stub path, if exposed.
3. Unsigned process domain / signed process domain option, if exposed.
4. HTP backend/architecture selection, if exposed.
5. Performance-control option only if needed for delegate initialization.

Acceptance:

- QNN transport/skel setup succeeds, even if a model is later rejected; or
- each option is ruled out with a log artifact that still shows the same native
  transport failure.

Do not tune thread counts or model preprocessing in this phase.

---

## 7. Phase 3: LiteRT Next Spike

Start this phase if:

- a new target device fails the existing TFLite/QNN delegate path; or
- we need portable MediaTek/Qualcomm coverage beyond the current proven
  Snapdragon path; or
- LiteRT metadata/API probe shows a stable version worth pinning and the current
  V0b proof is protected by regression gates.

Goal:

- run one existing `.tflite` model through LiteRT Next `CompiledModel` with NPU
  requested;
- capture whether LiteRT Next reaches QNN/HTP transport successfully;
- compare failure mode with the existing TFLite QNN delegate.

Decision:

- If LiteRT Next succeeds at transport where the old delegate fails, make it the
  primary Android acceleration migration path.
- If LiteRT Next fails with the same transport/skel markers, treat the blocker
  as device/runtime/packaging/unsigned-PD level, not a TFLite delegate-specific
  issue.

---

## 8. Phase 4: Diagnostic Cross-Checks

Only use these after the cheaper probes fail to decide the cause.

### Qualcomm AI Hub context binary

Use when LiteRT Next reaches transport but steady-state performance or first-run
compile behavior is still a problem on flagship Snapdragon.

### ONNX Runtime QNN

Use only to answer one question: does another QNN runtime fail at the same
transport layer on this phone?

If ONNX Runtime QNN fails with the same transport/skel error, stop treating
model export as the primary suspect.

### ExecuTorch QNN

Defer until after V0b unless LiteRT/QNN proves fundamentally unsuitable.

---

## 9. Stop Gates

Stop and report after any of these:

1. QNN transport succeeds for the existing app path.
2. Phase 1 proves a clear packaging/layout defect.
3. Phase 2 exhausts exposed delegate options without changing the transport
   failure.
4. LiteRT Next succeeds or fails with a clearly comparable transport result.

At each stop gate, update `docs/status/active/v0-implementation.md` with the
artifact path and the next decision.
