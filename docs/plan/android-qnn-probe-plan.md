# Android QNN Probe Plan

> Focused diagnosis plan for the Snapdragon 8 Gen 2 performance blocker found
> during V0b testing. This plan decides which Android acceleration options are
> worth trying now, and which should wait until the QNN transport failure is
> better understood.

**Status:** accepted for diagnosis / 2026-05-30.

---

## 1. Current Finding

The current Xiaomi target-class phone is not just slow. It reports QNN HTP
capability, but native QNN logs fail before either model can prove operator
compatibility:

- Device: Xiaomi `2211133C`, `SM8550`, board `kalama`, Android 16 / HyperOS
  `OS3.0.307.0.WMCCNXM`.
- Key artifact: `logs/qnn-smoke-full-20260529T154349Z.log`.
- Failure markers:
  - `QnnDsp loadRemoteSymbols failed with err 4000`;
  - `Failed to create transport for device`;
  - `Failed to load skel`;
  - `Transport layer setup failed: 14001`.

Working assumption: this is a QNN DSP transport / skeleton setup issue, not yet
a YOLO11n or Depth Anything model compatibility issue.

---

## 2. Decision

Do **not** implement every acceleration option now.

Run a short true-device probe first, then decide whether to invest in the
heavier alternatives. The first goal is to make QNN transport creation succeed
for any small path. FPS tuning and CPU fallback optimization stay out of scope
until the transport/skeleton root cause is known.

---

## 3. Ranked Options

| Rank | Option | Try now? | Why |
|---|---:|---|---|
| 1 | QNN package/layout probe | Yes | Lowest cost and most directly targets `Failed to load skel` / transport setup. |
| 2 | Minimal QNN delegate option spike | Yes, after probe | Worth trying only after we know installed paths, libraries, and ABI layout. |
| 3 | LiteRT Next `CompiledModel` spike | Next if current QNN path remains blocked | Highest strategic value, but heavier than a probe. May bypass current delegate packaging/skel issues. |
| 4 | Qualcomm AI Hub context binary | Later | Useful flagship fast path, but adds precompiled asset variables before transport is understood. |
| 5 | ONNX Runtime QNN cross-check | Diagnostic only | Good for proving whether QNN transport fails outside TFLite; not the product runtime choice. |
| 6 | ExecuTorch QNN | Defer | Real backend exists, but migration to `.pte` and PyTorch mobile flow is too heavy for this blocker. |
| 7 | CPU fallback performance profile | Not now | User explicitly wants the actual QNN issue found first; fallback tuning can hide the real failure. |

---

## 4. Phase 1: True-Device QNN Probe

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

## 5. Phase 2: Minimal QNN Delegate Option Spike

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

Do not tune thread counts, CPU fallback behavior, or model preprocessing in this
phase.

---

## 6. Phase 3: LiteRT Next Spike

Start this phase if:

- Phase 1/2 show the existing TFLite QNN delegate path is blocked by packaging
  or transport setup; or
- the delegate options are unavailable or insufficient on this device.

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

## 7. Phase 4: Diagnostic Cross-Checks

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

## 8. Stop Gates

Stop and report after any of these:

1. QNN transport succeeds for the existing app path.
2. Phase 1 proves a clear packaging/layout defect.
3. Phase 2 exhausts exposed delegate options without changing the transport
   failure.
4. LiteRT Next succeeds or fails with a clearly comparable transport result.

At each stop gate, update `docs/status/active/v0-implementation.md` with the
artifact path and the next decision.
