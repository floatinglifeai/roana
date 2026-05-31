# Roana Architecture

Roana is a cross-platform, on-device assistive navigation system. Its current V0
architecture is phone-first: Android and iOS each own their platform camera and
ML runtime, while both implementations converge on the same corridor-decision
contract.

## System Shape

```text
Camera frames
  -> obstacle detection
  -> monocular depth
  -> 15x15 corridor grid
  -> corridor command: STRAIGHT / LEFT / RIGHT / STOP
  -> speech feedback now, haptics later
```

The safety loop is intentionally small. Large vision-language models are not in
the always-on path.

## Platform Runtimes

### Android

Android lives in `app/`.

Key pieces:

- Camera: CameraX `ImageAnalysis` with `YUV_420_888` frames.
- Object detection: YOLO11n TFLite.
- Depth: Depth Anything V2 TFLite.
- Acceleration: Qualcomm QNN HTP through the TFLite delegate on target devices.
- Feedback: Android `TextToSpeech`.
- Safety: QNN-required runtime policy, frame-loss STOP, low-confidence STOP,
  and near-obstacle STOP.

Android keeps CPU/XNNPACK fallback out of production inference. Diagnostic smoke
tools may inspect CPU metadata, but the app gate treats missing QNN support as
unavailable rather than silently degrading.

### iOS

iOS lives in `ios/Roana/`.

Key pieces:

- Camera: AVFoundation + SwiftUI preview.
- Object detection: YOLO11n Core ML through Vision.
- Depth: Depth Anything V2 Small Core ML.
- Acceleration: Core ML with all compute units, targeting Apple Neural Engine
  where the compiled model/runtime permits it.
- Feedback: `AVSpeechSynthesizer` with a spoken-audio session.
- Safety: single-flight inference scheduling, frame-loss STOP in corridor mode,
  low-confidence STOP, background camera stop/restart handling, and
  camera-only privacy boundaries.

iOS model execution is launch-mode gated. The default app scheme is a no-model
camera path; YOLO and corridor/depth runs are explicit schemes or environment
settings.

## Shared Domain Contract

The shared behavior is a domain contract, not a shared binary.

Core concepts:

- `CorridorPlanner`: searches a 15x15 grid for a safe forward corridor.
- `CorridorStateMachine`: stabilizes guidance over multiple frames and allows
  immediate emergency STOP.
- `CorridorGridFusion`: combines depth with high-confidence obstacle detections.
- `CorridorPipeline`: produces guidance and feedback events from a frame's
  perception outputs.
- `MotionQuality`: separates trustworthy motion from unstable or unavailable
  motion context.

Android owns the Kotlin implementation. iOS owns the Swift implementation.
Parity is checked through `parity/corridor-core.json` and local Swift/Kotlin
tests instead of through Kotlin Multiplatform.

## Model Assets

Android model assets are app/runtime specific and are validated through device
smoke gates.

iOS model assets are intentionally not committed. The expected names and
contracts are recorded in:

```text
ios/Roana/Roana/ModelAssets/manifest.json
```

Local staging and validation commands:

```bash
scripts/install-ios-model-assets.py --model yolo11n --source /path/to/YOLO11n.mlpackage --symlink
scripts/install-ios-model-assets.py --model depth-anything-v2-small --source /path/to/DepthAnythingV2Small.mlpackage --symlink
scripts/check-ios-model-assets.py --require-present
```

## Verification Boundary

Roana uses scripts as executable proof gates.

Android:

```bash
scripts/build-debug.sh
scripts/verify-v0a-device.sh
scripts/verify-v0b-device.sh
scripts/verify-qnn-smoke-device.sh
```

iOS:

```bash
scripts/verify-ios-s0-local.sh
scripts/verify-ios-device-log.py --gate s0 --log logs/ios-skeleton-<timestamp>.log
ROANA_IOS_DEVELOPMENT_TEAM=<team-id> scripts/run-ios-v0b-physical.py
```

LiteRT validation:

```bash
scripts/build-litert-smoke-debug.sh
scripts/verify-litert-smoke-device.sh
scripts/compile-litert-qualcomm-aot.sh
```

## Extension Points

- Add a new Android accelerator by implementing a strict backend selection path
  and proving it through a smoke gate before it can be production runtime.
- Add a new iOS model by extending the model-asset manifest, bundle lookup, and
  physical/replay log gates.
- Add a new feedback channel by keeping speech/haptic semantics separated:
  speech carries meaning; haptics should carry direction and urgency.
- Add a glasses camera source by preserving the corridor-domain contract and
  swapping only the frame source/platform adapter.

