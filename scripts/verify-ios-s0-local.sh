#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios/Roana"
PROJECT="$IOS_DIR/Roana.xcodeproj/project.pbxproj"
INFO_PLIST="$IOS_DIR/Roana/Info.plist"
SMOKE_BINARY="$IOS_DIR/.corridor-core-smoke"

cleanup() {
  rm -f "$SMOKE_BINARY"
}
trap cleanup EXIT

required_files=(
  "$ROOT_DIR/ios/AGENTS.md"
  "$PROJECT"
  "$INFO_PLIST"
  "$IOS_DIR/Roana/RoanaApp.swift"
  "$IOS_DIR/Roana/ContentView.swift"
  "$IOS_DIR/Roana/Camera/CameraAuthorization.swift"
  "$IOS_DIR/Roana/Camera/FrameInferenceCoordinator.swift"
  "$IOS_DIR/Roana/Camera/CameraPreviewView.swift"
  "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
  "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift"
  "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift"
  "$IOS_DIR/Roana/Corridor/CorridorGridFusion.swift"
  "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift"
  "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift"
  "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
  "$IOS_DIR/Roana/Diagnostics/DeviceDiagnostics.swift"
  "$IOS_DIR/Roana/Diagnostics/FrameDiagnostics.swift"
  "$IOS_DIR/Roana/Diagnostics/RollingPercentileWindow.swift"
  "$IOS_DIR/Roana/ModelAssets/manifest.json"
  "$IOS_DIR/Roana/ModelAssets/README.md"
  "$IOS_DIR/Roana/Models/ModelAssetResourceLocator.swift"
  "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
  "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift"
  "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
  "$IOS_DIR/RoanaTests/Depth/main.swift"
  "$IOS_DIR/RoanaTests/Inference/main.swift"
  "$IOS_DIR/RoanaTests/main.swift"
  "$IOS_DIR/RoanaTests/Privacy/main.swift"
  "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana.xcscheme"
)

for path in "${required_files[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "missing required iOS-S0 file: ${path#$ROOT_DIR/}" >&2
    exit 1
  fi
done

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
python3 -m json.tool "$IOS_DIR/Roana/Assets.xcassets/Contents.json" >/dev/null
python3 -m json.tool "$IOS_DIR/Roana/ModelAssets/manifest.json" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_analyze_ios_log.py" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_check_ios_model_assets.py" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_install_ios_model_assets.py" >/dev/null
python3 "$ROOT_DIR/scripts/check-ios-model-assets.py" \
  --manifest "$IOS_DIR/Roana/ModelAssets/manifest.json" >/dev/null
python3 - <<'PY' "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana.xcscheme"
import sys
import xml.etree.ElementTree as ET

ET.parse(sys.argv[1])
PY

grep -q "NSCameraUsageDescription" "$INFO_PLIST"
grep -q "AVCaptureVideoDataOutput" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "kCVPixelFormatType_420YpCbCr8BiPlanarFullRange" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "alwaysDiscardsLateVideoFrames = true" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "DispatchQueue(label: \"app.roana.ios.camera.frames\")" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "FrameInferenceCoordinator<CMSampleBuffer>" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "inferenceCoordinator.submit(sampleBuffer)" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "app.roana.ios.inference" "$IOS_DIR/Roana/Camera/FrameInferenceCoordinator.swift"
grep -q "roana_ios_inference" "$IOS_DIR/Roana/Camera/FrameInferenceCoordinator.swift"
grep -q "UIApplication.shared.isIdleTimerDisabled = true" "$IOS_DIR/Roana/ContentView.swift"
grep -q "roana_ios_frame_stats" "$IOS_DIR/Roana/Diagnostics/FrameDiagnostics.swift"
grep -q "camera_background_stop" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "DepthAnythingRunner()" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "corridorPipeline.process" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "VNCoreMLRequest" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "VNRecognizedObjectObservation" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "AVSpeechSynthesizer" "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
grep -q "roana_ios_yolo" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "roana_ios_speech" "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
grep -q "near_obstacle" "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift"
grep -q "frame_loss" "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift"
grep -q "low_confidence" "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift"
grep -q "roana_ios_corridor" "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift"
grep -q "roana_ios_corridor_feedback" "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift"
grep -q "feedbackDispatcher" "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift"
grep -q "MLMultiArray" "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift"
grep -q "expectedInputWidth = 518" "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift"
grep -q "roana_ios_depth" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "computeUnits = .all" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "ModelAssetResourceLocator" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "ModelAssetResourceLocator" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "ModelAssetResourceLocator.swift in Sources" "$PROJECT"
grep -q "ModelAssets in Resources" "$PROJECT"
grep -q "Do not upload video frames" "$ROOT_DIR/ios/AGENTS.md"
grep -q "Low confidence, missing frames" "$ROOT_DIR/ios/AGENTS.md"
grep -q "scripts/verify-ios-s0-local.sh" "$ROOT_DIR/ios/AGENTS.md"
grep -q "scripts/analyze-ios-log.py" "$ROOT_DIR/ios/AGENTS.md"

swiftc \
  "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorGridFusion.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift" \
  "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift" \
  "$IOS_DIR/RoanaTests/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" >/dev/null

swiftc \
  "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorGridFusion.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift" \
  "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift" \
  "$IOS_DIR/RoanaTests/Parity/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" "$ROOT_DIR/parity/corridor-core.json" >/dev/null

swiftc \
  "$IOS_DIR/Roana/Camera/FrameInferenceCoordinator.swift" \
  "$IOS_DIR/RoanaTests/Inference/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" >/dev/null

swiftc \
  "$IOS_DIR/RoanaTests/Privacy/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" "$ROOT_DIR" >/dev/null

swiftc \
  "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift" \
  "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift" \
  "$IOS_DIR/RoanaTests/Depth/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" >/dev/null

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild unavailable; iOS local structural checks passed, build deferred" >&2
  exit 2
fi

if ! xcode_version="$(xcodebuild -version 2>&1)"; then
  if grep -q "requires Xcode" <<<"$xcode_version"; then
    echo "xcodebuild requires full Xcode; iOS local structural checks passed, build deferred" >&2
    exit 2
  fi
  echo "$xcode_version" >&2
  exit 1
fi

xcodebuild \
  -project "$IOS_DIR/Roana.xcodeproj" \
  -scheme Roana \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
