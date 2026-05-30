# iOS V0b Performance Status

Updated: 2026-05-30.

## Summary

The iOS V0b physical path now reaches the app on the real iPhone and produces
machine-checkable corridor logs. The current implementation does not yet pass
the V0b physical gate because sustained corridor mode overheats and skips too
many inference frames.

The remaining blocker is performance/thermal, not signing, device visibility,
model asset presence, camera startup, or log capture.

## Device And Artifacts

- Device: `MiaoDX003`, iPhone Air (`iPhone18,4`), iOS `26.3.1`.
- CoreDevice ID: `A85B7E8D-1EDD-573F-9C50-BC76B9FB8E03`.
- Build mode: `Roana-V0b-Corridor`.
- Launch mode: `--roana-enable-corridor --roana-debug-fail-safe-stop`.
- Team ID was supplied with `ROANA_IOS_DEVELOPMENT_TEAM`; it is not committed.

Local artifacts:

- `logs/ios-v0b-20260530T154240Z.log`
- `logs/ios-v0b-20260530T154654Z.log`

The log artifacts are local evidence and are not tracked by git.

## What Passed

Both physical runs proved the app can build, install, launch, and execute the
model-backed corridor path on the iPhone.

The second run is the better procedural artifact:

- `max_run_seconds`: `99.6`
- `background_cycle_seen`: `true`
- `camera_background_stop`: `true`
- `camera_started`: `true`
- `permission_seen`: `true`
- `model_modes`: `corridor`
- `YOLO11n` model description present
- `DepthAnythingV2Small` model description present
- YOLO Vision orientation evidence present
- Depth Vision orientation evidence present
- preview/capture orientation evidence present
- `corridor_feedback_spoken_count`: `74`
- normal guidance feedback present
- fail-safe STOP evidence present
- `max_p95_ms`: `100.01`
- `max_backlog`: `0`
- `max_dropped`: `0`

This means the core V0b iOS wiring is alive: camera frames reach YOLO and Depth
Anything, depth grids reach the corridor planner, speech feedback is queued, and
the debug frame-loss STOP path is observable.

## What Failed

First physical run:

- Artifact: `logs/ios-v0b-20260530T154240Z.log`
- `max_run_seconds`: `52.39`
- `background_cycle_seen`: `false`
- `camera_background_stop`: `false`
- `max_thermal_state`: `fair`
- `avg_depth_ms`: `79.32`
- `avg_yolo_ms`: `5.9`
- `max_inference_skipped`: `19`
- Missing gate evidence:
  - `run_s>=60`
  - `camera_background_stop`
  - `camera_background_restart`
  - `inference_skipped<=5`

Second physical run:

- Artifact: `logs/ios-v0b-20260530T154654Z.log`
- `max_run_seconds`: `99.6`
- `background_cycle_seen`: `true`
- `camera_background_stop`: `true`
- `max_thermal_state`: `serious`
- `avg_depth_ms`: `91.17`
- `avg_yolo_ms`: `6.73`
- `max_inference_skipped`: `222`
- Missing gate evidence:
  - `thermal<=fair`
  - `inference_skipped<=5`

The second run eliminated the procedural blockers and exposed the real V0b
blocker: sustained 10 FPS corridor inference is too close to or over the device
budget with the current model/runtime configuration.

## Current Interpretation

The app is configured for a 10 FPS corridor capture target. Frame cadence stays
near the gate (`p95_ms=100.01`) and camera output does not backlog, but the
single-flight inference coordinator drops model work whenever the previous
YOLO+Depth+planning pass has not finished. That behavior is intentional and
protects the capture queue from unbounded backlog.

The skip count shows the end-to-end model path cannot reliably finish every
100 ms during sustained V0b operation on the tested device. Depth Anything is
the dominant cost: the observed average depth time is about `79-91 ms`, before
including YOLO and corridor work. Thermal state reached `serious` during the
longer run.

The V0b verifier should not be loosened yet. It correctly distinguishes "the
physical iPhone path works" from "the corridor demo is safe enough to pass."

## Current Gate Command

Run the V0b physical wrapper when the iPhone is connected:

```bash
ROANA_IOS_DEVELOPMENT_TEAM=XP2NFR9M33 scripts/run-ios-v0b-physical.py --capture-seconds 110
```

During the run, background and reopen the app once after preview starts so the
background-cycle gate is covered.

Verify an existing artifact directly:

```bash
scripts/verify-ios-device-log.py --gate v0b \
  --log logs/ios-v0b-20260530T154654Z.log \
  --skip-host-checks --require-device 0
```

## Stop Condition

The current V0b physical gate remains blocked until a real iPhone artifact
passes all of:

- at least 60 seconds of run evidence,
- background stop/restart evidence,
- YOLO and Depth Anything model-description evidence,
- Vision orientation evidence,
- corridor feedback evidence,
- fail-safe STOP evidence,
- `p95 <= 100 ms`,
- thermal no worse than `fair`,
- inference skipped count no greater than `5`.

