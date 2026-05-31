# Roana Status

Updated: 2026-05-31

Roana is in V0 implementation. The repository now contains native Android and
iOS apps, model/runtime validation tools, replay tooling, and device gates. The
project is not yet a user-ready release.

## Current Product Slice

V0 is a phone-only corridor safety loop:

1. capture camera frames,
2. run on-device obstacle/depth perception,
3. fuse detections and depth into a corridor grid,
4. emit `STRAIGHT`, `LEFT`, `RIGHT`, or `STOP`,
5. speak guidance or fail-safe STOP feedback.

The white cane and O&M skills remain primary. Roana is an assistive companion,
not a replacement.

## Android

Android is the most proven runtime today.

- Native app lives in `app/`.
- V0a camera, YOLO, and TextToSpeech loop is implemented.
- V0b live corridor path runs YOLO and Depth Anything on Qualcomm QNN HTP on a
  Xiaomi `2211133C` / SM8550 / Snapdragon 8 Gen 2 target phone.
- Short V0b machine gate passed with QNN active, no severe frame gaps, normal
  corridor guidance feedback, and low-confidence safe STOP proof.
- 30-minute live-corridor thermal gate passed on the same target-class phone.
- Production Android inference is QNN-required. Missing QNN capability,
  delegate creation failure, or delegate application failure fails the gate
  instead of silently using CPU/XNNPACK.
- Remaining Android proof: known-corridor sighted-spotter run.

Useful commands:

```bash
scripts/build-debug.sh
scripts/verify-v0a-device.sh
scripts/verify-v0b-device.sh
scripts/verify-qnn-smoke-device.sh
```

## iOS

iOS is implemented enough for local gates and offline replay, but still needs
physical-device proof.

- Native SwiftUI app lives in `ios/Roana/`.
- Camera pipeline uses AVFoundation with a serial frame callback queue and
  single-flight inference scheduling.
- Model modes are explicit:
  - `Roana`: no-model S0 camera path
  - `Roana-V0a-YOLO`: YOLO-only V0a path
  - `Roana-V0b-Corridor`: YOLO + Depth + corridor V0b path
- Core ML model contract is defined under
  `ios/Roana/Roana/ModelAssets/manifest.json`.
- Swift corridor planner, state machine, grid fusion, depth adapter, speech
  feedback, motion-quality handling, and replay harness are implemented.
- Local replay passes with staged model assets and user-recorded local video
  fixtures that are intentionally not committed.
- Remaining iOS proof: physical iPhone launch/log capture for S0/V0a/V0b while
  the target device is available.

Useful commands:

```bash
scripts/verify-ios-s0-local.sh
scripts/check-ios-model-assets.py
scripts/check-ios-model-assets.py --require-present
ROANA_IOS_DEVELOPMENT_TEAM=<team-id> scripts/run-ios-v0b-physical.py
```

## LiteRT

LiteRT is paused as a production migration.

- Android production stays on TFLite + Qualcomm QNN HTP.
- LiteRT AOT validation can reach Qualcomm NPU, but the packaged Android smoke
  path was slower than the current QNN path.
- A source-built LiteRT `main` C++ stack with QAIRT 2.46 ran Roana YOLO and
  Depth on SM8550 NPU at production-relevant speed.
- The remaining blocker is Android app integration: a matched, release-quality
  LiteRT Android AAR plus Qualcomm provider/runtime bundle is not available in
  the public package path we tested.

See [docs/human/litert-qualcomm-follow-up.md](docs/human/litert-qualcomm-follow-up.md).

## Next Decisions

- Complete the Android known-corridor sighted-spotter proof.
- Complete iOS physical-device S0/V0a/V0b log capture once the iPhone is
  available.
- Keep Android production runtime QNN-required.
- Revisit LiteRT only when a matched Android provider release exists, or if we
  deliberately choose to own a native JNI integration layer.

