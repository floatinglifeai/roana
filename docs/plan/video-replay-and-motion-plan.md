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
- Treat IMU/motion as an optional cross-platform input for quality control:
  detect pointing-down, unstable, or high-motion frames before trusting guidance.

## Non-Goals

- Do not add production video recording or photo-library access to the app yet.
- Do not make LiDAR, ARKit, or platform-specific depth sensors required.
- Do not use motion data as a primary navigation signal before image replay is
  reliable.

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

`samples/home_iphone_0530.mp4` is a local development fixture and is not
committed. Keep full videos out of normal git history unless the project adopts
Git LFS or a separate fixture-fetch path.

## Remaining Discussion Questions

- Should we store only small derived replay logs, adopt Git LFS for selected
  fixture videos, or keep user-recorded videos local-only?
- Should replay stay only in scripts/tests, or also live behind a debug-only app
  mode?
- What minimum motion contract should both iOS and Android expose?
- Are command labels enough for V0b fixtures (`STRAIGHT`, `LEFT`, `RIGHT`,
  `STOP`), or should we also label scene quality such as `pointing_down` and
  `unstable`?
