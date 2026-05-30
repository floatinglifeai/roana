# Video Replay And Motion Plan

Draft for later discussion.

## Goal

Make indoor corridor testing repeatable without requiring a live tethered walk.
Use user-recorded phone video as an offline replay source, and consider a small
cross-platform motion signal for camera-quality checks.

## Candidate Scope

- Implemented: `scripts/replay-ios-video.sh` compiles a dev-only Swift replay
  tool that reads recorded video frames and feeds the same YOLO, Depth Anything,
  and corridor pipeline used by live camera runs.
- Implemented: replay emits existing `roana_ios_*`-style evidence logs so
  replay results can be compared with physical-device logs.
- Implemented: `scripts/verify-ios-replay-log.py` wraps replay-log analysis with
  explicit fixture modes. `--fixture stop` checks close-obstacle / STOP clips;
  `--fixture guidance` additionally requires a normal LEFT/STRAIGHT/RIGHT
  corridor utterance and audio-session evidence.
- Implemented contract: iOS and Android both define a small optional
  `MotionQuality` classifier for quality control labels. It detects
  `pointing_down` from pitch and `unstable` from angular velocity, and treats
  missing motion as `stable` so image-only replay and live camera runs continue
  to work.
- Implemented replay evidence: offline replay logs
  `roana_ios_motion_quality label=stable reason=motion_unavailable
  trusts_guidance=true source=replay`, and `scripts/verify-ios-replay-log.py`
  requires that evidence by default.
- Implemented local labeling helper: `scripts/label-ios-replay.py` turns a
  replay log, or a local video replayed through the same harness, into a small
  JSON summary with suggested command labels, scene-quality labels, and a
  `stop` / `guidance` / `mixed` / `review` fixture suggestion. The helper also
  emits approximate segment labels by assigning corridor decisions and spoken
  feedback to the most recent replay frame timestamp.
- Implemented local replay bundle helper: `scripts/run-ios-replay-bundle.py`
  runs replay, verification, and labeling in one command and writes the replay
  log, verification JSON, and label JSON to local artifact paths. The bundle
  helper defaults to `--fixture auto`: it labels first, verifies guidance clips
  as `guidance`, and verifies `stop` / `mixed` / `review` clips against the
  conservative STOP fixture.

## Non-Goals

- Do not add production video recording or photo-library access to the app yet.
- Do not make LiDAR, ARKit, or platform-specific depth sensors required.
- Do not use motion data as a primary navigation signal before image replay is
  reliable.
- Do not add real sensor collection or new app permissions until the quality
  contract is wired into a gated debug/live path.

## Current Commands

Run a short replay smoke against a local video:

```bash
scripts/replay-ios-video.sh samples/home_iphone_0530.mp4 --fps 1 --max-seconds 2 \
  | tee /tmp/roana-ios-video-replay-smoke.log
```

Verify the resulting STOP fixture log:

```bash
scripts/verify-ios-replay-log.py --log /tmp/roana-ios-video-replay-smoke.log \
  --fixture stop --min-run-seconds 2 --max-p95-ms 1000
```

Run a longer guidance replay against the same local sample:

```bash
scripts/replay-ios-video.sh samples/home_iphone_0530.mp4 --fps 2 --max-seconds 20 \
  | tee /tmp/roana-ios-video-replay-guidance-probe.log
```

Verify the resulting guidance fixture log:

```bash
scripts/verify-ios-replay-log.py --log /tmp/roana-ios-video-replay-guidance-probe.log \
  --fixture guidance --min-run-seconds 20 --max-p95-ms 500
```

Create a local label summary from an existing replay log:

```bash
scripts/label-ios-replay.py --from-log /tmp/roana-ios-video-replay-guidance-probe.log \
  --summary /tmp/roana-ios-video-replay-guidance-probe.labels.json
```

Or replay and label a local video in one command:

```bash
scripts/label-ios-replay.py samples/home_iphone_0530.mp4 --fps 2 --max-seconds 20 \
  --log /tmp/roana-ios-video-replay-guidance-probe.log \
  --summary /tmp/roana-ios-video-replay-guidance-probe.labels.json
```

Create the replay log, verification JSON, and label JSON in one local bundle:

```bash
scripts/run-ios-replay-bundle.py samples/home_iphone_0530.mp4 \
  --fps 2 --max-seconds 20 \
  --min-run-seconds 20 --max-p95-ms 500
```

By default, bundle artifacts are written under `/tmp` with names like
`roana-ios-replay-<video>-<timestamp>.log`, `.verify.json`, and `.labels.json`.
Pass `--fixture guidance` or `--fixture stop` only when you want to force a
specific gate instead of using the label-derived `auto` choice.

`samples/home_iphone_0530.mp4` is a local development fixture and is ignored by
git. Keep full videos out of normal git history unless the project adopts Git
LFS or a separate fixture-fetch path. `samples/README.md` records the current
local-only policy and the replay label vocabulary. Label summaries are small
metadata, but still review them before committing because they can encode scene
content from a private video. Segment timestamps are approximate replay evidence
timestamps, not hand-reviewed ground truth.

Current V0b replay labels:

- Command labels: `STOP`, `STRAIGHT`, `LEFT`, `RIGHT`.
- Scene-quality labels: `pointing_down`, `unstable`, `too_close`, `occluded`.
- `stop` fixtures must prove STOP behavior. `guidance` fixtures must prove at
  least one normal LEFT / STRAIGHT / RIGHT corridor utterance.

## Motion Quality Contract

The cross-platform contract is intentionally quality-control-only:

- `MotionQuality.Label.STABLE` / `stable`: guidance can use image/depth output.
- `MotionQuality.Label.POINTING_DOWN` / `pointing_down`: phone pitch is at or
  below -55 degrees; guidance should be considered untrusted until the camera is
  raised.
- `MotionQuality.Label.UNSTABLE` / `unstable`: absolute angular velocity is at
  or above 120 degrees per second; guidance should be considered untrusted until
  motion settles.
- Missing motion data returns `stable` with reason `motion_unavailable`, so V0b
  remains image-first and cross-platform.

Current code only defines and tests this shared contract. It does not collect
iOS Core Motion / Android sensor data, alter corridor decisions, or add
permissions. Replay uses the `motion_unavailable` path to make that image-first
fallback explicit in generated logs.

## Remaining Discussion Questions

- Should selected videos or scrubbed label summaries move to Git LFS /
  fixture-fetch later, or should all user-recorded replay artifacts remain
  local-only?
- Should replay stay only in scripts/tests, or also live behind a debug-only app
  mode?
- Are command labels enough for V0b fixtures (`STRAIGHT`, `LEFT`, `RIGHT`,
  `STOP`), or should we also label scene quality such as `pointing_down` and
  `unstable`?
