# iOS V0b Performance Improvement Plan

Draft for implementation discussion.

## Goal

Make the iOS V0b corridor demo pass the physical iPhone gate without weakening
the safety contract. The target remains sustained corridor guidance at the V0b
gate: at least 60 seconds, p95 frame cadence at or below 100 ms, no backlog, no
excess inference skips, and thermal no worse than `fair`.

## Starting Evidence

The current best physical artifact is
`logs/ios-v0b-20260530T154654Z.log`.

It proves:

- app launch, camera startup, model loading, and log capture work;
- background stop/restart evidence can be produced;
- YOLO and Depth Anything both run with matching Vision orientation;
- corridor feedback and fail-safe STOP are observable;
- frame cadence stays at about `100.01 ms`;
- camera backlog and dropped frames remain `0`.

It blocks on:

- `max_inference_skipped=222`, gate requires `<=5`;
- `max_thermal_state=serious`, gate requires no worse than `fair`;
- `avg_depth_ms=91.17`, leaving little budget for YOLO, planning, speech, and
  thermal variation inside a 100 ms frame interval.

## Non-Goals

- Do not loosen the V0b physical verifier to hide performance failures.
- Do not add production recording, network upload, cloud inference, VLM calls,
  identity recognition, or frame storage.
- Do not commit large Core ML model binaries or private device logs.
- Do not add platform-specific sensors as a required navigation signal.
- Do not resume Android/JDK/QNN work in this iOS worktree.

## Phase 1: Better Measurement

Add enough local evidence to separate model/runtime problems from scheduling
and thermal problems.

Tasks:

- Extend iOS log analysis to report p50/p95/max for YOLO latency and depth
  latency, not only averages.
- Report skip rate as skipped frames divided by total frame stats and accepted
  inference frames.
- Report thermal transition timing, especially when state first reaches `fair`
  and `serious`.
- Preserve the current fail-safe STOP and frame-loss evidence requirements.

Acceptance:

- Existing analyzer tests cover the new latency and thermal summary fields.
- Re-running verification on existing logs shows the same pass/block status but
  richer diagnostics.

## Phase 2: Confirm Model Asset And Compute Path

Verify that the bundled Depth Anything model is the expected optimized Core ML
resource and that Core ML is using the intended accelerator path.

Tasks:

- Inspect the local `DepthAnythingV2Small.mlmodelc` provenance and compile
  settings outside git.
- Add local-only documentation for how the model was obtained or compiled.
- If available from Core ML metadata or runtime diagnostics, log enough compute
  information to distinguish intended ANE/all-compute execution from CPU-heavy
  fallback.
- Compare the observed physical latency against a minimal depth-only run so
  corridor, YOLO, and speech overhead are not mixed into the model check.

Acceptance:

- We can say whether the current depth asset is the expected optimized model.
- A depth-only physical artifact records depth latency distribution and thermal
  state for at least 60 seconds.

## Phase 3: Isolate Pipeline Cost

Run targeted physical gates that enable one subsystem at a time.

Candidate runs:

- S0 camera only: verifies baseline camera cadence and thermal behavior.
- V0a YOLO only: verifies YOLO latency and speech overhead.
- depth-only debug mode: verifies Depth Anything cost without YOLO/corridor.
- V0b full corridor: verifies end-to-end behavior after changes.

Acceptance:

- Each run has a local artifact and verifier summary.
- The dominant cause of skips is classified as one of:
  - depth model too slow,
  - model warmup/first-run spikes,
  - sustained thermal throttling,
  - scheduling too aggressively,
  - non-model corridor/speech overhead.

## Phase 4: Scheduling And Thermal Control

If the model asset is correct but sustained full-rate inference remains too hot,
make corridor inference intentionally budgeted instead of opportunistically
racing every camera frame.

Candidate changes:

- Keep camera preview at 10 FPS, but target corridor inference at a configurable
  cadence such as 5-8 FPS.
- Log intentional cadence skips separately from `busy` skips so the verifier can
  distinguish controlled scheduling from overload.
- Add thermal-aware behavior:
  - `nominal`: normal corridor cadence;
  - `fair`: reduce corridor cadence;
  - `serious`: emit conservative STOP / low-confidence guidance and stop
    trusting new guidance until thermal recovers.
- Keep single-flight inference to prevent capture queue backlog.

Acceptance:

- Controlled cadence does not produce unbounded backlog.
- If cadence is intentionally below 10 FPS, the product/safety gate is updated
  explicitly rather than silently weakening the existing V0b verifier.
- A physical artifact proves the chosen behavior for at least 60 seconds.

## Phase 5: Model Optimization Options

If scheduling alone cannot meet the gate, evaluate model-side options.

Options:

- Confirm or replace the Depth Anything Core ML resource with the intended
  optimized Apple/Hugging Face package.
- Test a smaller or lower-precision depth model if the product can tolerate it.
- Reduce input size only if the output adapter and corridor safety thresholds
  are revalidated.
- Consider running depth less frequently than YOLO while holding the last
  trusted depth grid for a short bounded interval.

Acceptance:

- Any model change preserves conservative STOP behavior on uncertainty.
- Swift parity and depth-adapter tests still pass.
- A new physical artifact beats the current baseline on depth latency, skipped
  inference, and thermal state.

## Verification Commands

Local code gate:

```bash
scripts/verify-ios-s0-local.sh
```

Physical V0b gate:

```bash
ROANA_IOS_DEVELOPMENT_TEAM=XP2NFR9M33 scripts/run-ios-v0b-physical.py --capture-seconds 110
```

Existing artifact verifier:

```bash
scripts/verify-ios-device-log.py --gate v0b \
  --log logs/ios-v0b-20260530T154654Z.log \
  --skip-host-checks --require-device 0
```

## Decision Point

After Phase 1-3 measurement, choose one of:

- keep the current 10 FPS V0b target and optimize the model/runtime until it
  passes;
- explicitly redefine the V0b iOS corridor gate around a lower intentional
  inference cadence while keeping camera preview smooth and STOP behavior
  conservative;
- defer iOS V0b on this device class and require a faster supported iPhone for
  the first corridor demo.

