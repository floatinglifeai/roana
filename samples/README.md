# Local Sample Fixtures

This directory is for local replay videos used during development. Full video
files are ignored by git by default.

Current policy:

- Keep user-recorded `.mp4` / `.mov` files local-only unless the project adopts
  Git LFS or a separate fixture-fetch path.
- Commit derived replay logs or small metadata fixtures only when they are
  scrubbed and useful for automated verification.
- Use `scripts/replay-ios-video.sh` to generate logs from a local video, then
  verify the log with `scripts/verify-ios-replay-log.py`.
- Use `scripts/label-ios-replay.py --from-log <replay.log>` to create a small
  clip-level label summary from replay evidence. It also includes approximate
  segment labels based on replay frame timestamps. The summary is metadata only;
  videos remain local-only by default.

V0b replay labels:

- Command labels: `STOP`, `STRAIGHT`, `LEFT`, `RIGHT`.
- Scene-quality labels: `pointing_down`, `unstable`, `too_close`, `occluded`.
- A `stop` fixture must prove STOP behavior; a `guidance` fixture must prove at
  least one normal `LEFT` / `STRAIGHT` / `RIGHT` corridor utterance.
