# Video Replay And Motion Plan

Draft for later discussion.

## Goal

Make indoor corridor testing repeatable without requiring a live tethered walk.
Use user-recorded phone video as an offline replay source, and consider a small
cross-platform motion signal for camera-quality checks.

## Candidate Scope

- Add a dev-only video replay path that reads recorded video frames and feeds the
  same YOLO, Depth Anything, and corridor pipeline used by live camera runs.
- Emit the existing `roana_ios_*`-style evidence logs so replay results can be
  compared with physical-device logs.
- Treat IMU/motion as an optional cross-platform input for quality control:
  detect pointing-down, unstable, or high-motion frames before trusting guidance.

## Non-Goals

- Do not add production video recording or photo-library access to the app yet.
- Do not make LiDAR, ARKit, or platform-specific depth sensors required.
- Do not use motion data as a primary navigation signal before image replay is
  reliable.

## Discussion Questions

- What video fixture format and storage policy should we use?
- Should replay live only in scripts/tests, or also behind a debug-only app mode?
- What minimum motion contract should both iOS and Android expose?
- Which replay labels are enough for V0b: `STRAIGHT`, `LEFT`, `RIGHT`, `STOP`,
  or also scene-quality labels like `pointing_down` and `unstable`?
