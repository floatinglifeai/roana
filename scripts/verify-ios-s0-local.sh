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
  "$IOS_DIR/Roana/Camera/CameraFrameOrientation.swift"
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
  "$IOS_DIR/Roana/Models/ModelDescriptionLogger.swift"
  "$IOS_DIR/Roana/Models/ModelInferenceMode.swift"
  "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
  "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift"
  "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift"
  "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
  "$IOS_DIR/Roana/Speech/YoloSpeechFeedbackPolicy.swift"
  "$IOS_DIR/RoanaTests/ModelAssets/main.swift"
  "$IOS_DIR/RoanaTests/ModelMode/main.swift"
  "$IOS_DIR/RoanaTests/Depth/main.swift"
  "$IOS_DIR/RoanaTests/Inference/main.swift"
  "$IOS_DIR/RoanaTests/main.swift"
  "$IOS_DIR/RoanaTests/Privacy/main.swift"
  "$IOS_DIR/RoanaTests/Speech/main.swift"
  "$IOS_DIR/RoanaTests/VideoReplay/main.swift"
  "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana.xcscheme"
  "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana-V0a-YOLO.xcscheme"
  "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana-V0b-Corridor.xcscheme"
  "$ROOT_DIR/scripts/capture-ios-device-log.py"
  "$ROOT_DIR/scripts/test_capture_ios_device_log.py"
  "$ROOT_DIR/scripts/check-ios-xcodeproj-membership.py"
  "$ROOT_DIR/scripts/test_check_ios_xcodeproj_membership.py"
  "$ROOT_DIR/scripts/generate-corridor-parity-fixtures.py"
  "$ROOT_DIR/scripts/replay-ios-video.sh"
  "$ROOT_DIR/scripts/test_generate_corridor_parity_fixtures.py"
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
python3 -m unittest "$ROOT_DIR/scripts/test_capture_ios_device_log.py" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_check_ios_model_assets.py" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_check_ios_xcodeproj_membership.py" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_generate_corridor_parity_fixtures.py" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_install_ios_model_assets.py" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_ios_privacy_boundary.py" >/dev/null
python3 -m unittest "$ROOT_DIR/scripts/test_verify_ios_device_log.py" >/dev/null
python3 "$ROOT_DIR/scripts/check-ios-xcodeproj-membership.py" >/dev/null
grep -q "allow-large-copy" "$ROOT_DIR/scripts/install-ios-model-assets.py"
grep -q "matched_yolo_speech_labels" "$ROOT_DIR/scripts/analyze-ios-log.py"
grep -q "yolo_speech_match" "$ROOT_DIR/scripts/analyze-ios-log.py"
grep -q "audio_session_active" "$ROOT_DIR/scripts/analyze-ios-log.py"
grep -q "ARTIFACT_PREFIX" "$ROOT_DIR/scripts/capture-ios-device-log.py"
grep -q "ios-skeleton" "$ROOT_DIR/scripts/capture-ios-device-log.py"
grep -q "verify-ios-device-log.py" "$ROOT_DIR/scripts/capture-ios-device-log.py"
python3 "$ROOT_DIR/scripts/check-ios-model-assets.py" \
  --manifest "$IOS_DIR/Roana/ModelAssets/manifest.json" >/dev/null
grep -q '"expectedOutputs"' "$IOS_DIR/Roana/ModelAssets/manifest.json"
grep -q '"VNRecognizedObjectObservation"' "$IOS_DIR/Roana/ModelAssets/manifest.json"
grep -q '"MLMultiArray"' "$IOS_DIR/Roana/ModelAssets/manifest.json"
grep -q '"VNPixelBufferObservation"' "$IOS_DIR/Roana/ModelAssets/manifest.json"
python3 - <<'PY' "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana.xcscheme" "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana-V0a-YOLO.xcscheme" "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana-V0b-Corridor.xcscheme"
import sys
import xml.etree.ElementTree as ET

for path in sys.argv[1:]:
    ET.parse(path)
PY

grep -q -- "--roana-enable-yolo" "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana-V0a-YOLO.xcscheme"
grep -q -- "--roana-enable-corridor" "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana-V0b-Corridor.xcscheme"
grep -q -- "--roana-debug-fail-safe-stop" "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana-V0b-Corridor.xcscheme"
if grep -q -- "--roana-enable-yolo\\|--roana-enable-corridor" "$IOS_DIR/Roana.xcodeproj/xcshareddata/xcschemes/Roana.xcscheme"; then
  echo "Default Roana scheme must remain no-model S0" >&2
  exit 1
fi

grep -q "NSCameraUsageDescription" "$INFO_PLIST"
grep -q "AVCaptureVideoDataOutput" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "kCVPixelFormatType_420YpCbCr8BiPlanarFullRange" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "alwaysDiscardsLateVideoFrames = true" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "DispatchQueue(label: \"app.roana.ios.camera.frames\")" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "FrameInferenceCoordinator<CMSampleBuffer>" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "inferenceCoordinator.submit(sampleBuffer)" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "ModelInferenceMode.current()" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "roana_ios_model_mode" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "inferenceMode.runsYolo ? YoloObstacleDetector() : nil" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "inferenceMode.runsDepth ? DepthAnythingRunner() : nil" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "modelInferenceMode.runsYolo" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "modelInferenceMode.runsDepth" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "guard modelInferenceMode.runsDepth" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "ROANA_IOS_MODEL_MODE" "$IOS_DIR/Roana/Models/ModelInferenceMode.swift"
grep -q "resolve(arguments:" "$IOS_DIR/Roana/Models/ModelInferenceMode.swift"
grep -q -- "--roana-enable-yolo" "$IOS_DIR/Roana/Models/ModelInferenceMode.swift"
grep -q -- "--roana-enable-corridor" "$IOS_DIR/Roana/Models/ModelInferenceMode.swift"
grep -q "ModelInferenceMode.swift in Sources" "$PROJECT"
grep -q "failSafeStop(reason: \"frame_loss\")" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "roana_ios_safety event=fail_safe_stop" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "roana_ios_safety debug_fail_safe_stop enabled=true reason=frame_loss" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "ROANA_DEBUG_FAIL_SAFE_STOP" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q -- "--roana-debug-fail-safe-stop" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "app.roana.ios.inference" "$IOS_DIR/Roana/Camera/FrameInferenceCoordinator.swift"
grep -q "roana_ios_inference" "$IOS_DIR/Roana/Camera/FrameInferenceCoordinator.swift"
grep -q "UIApplication.shared.isIdleTimerDisabled = disabled" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "idle_timer_disabled value=" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
if grep -q "isIdleTimerDisabled" "$IOS_DIR/Roana/ContentView.swift"; then
  echo "ContentView must not control UIApplication.isIdleTimerDisabled directly" >&2
  exit 1
fi
grep -q "roana_ios_frame_stats" "$IOS_DIR/Roana/Diagnostics/FrameDiagnostics.swift"
grep -q "run_s=" "$IOS_DIR/Roana/Diagnostics/FrameDiagnostics.swift"
grep -q "camera_background_stop" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "camera_permission_denied" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "camera_output_orientation" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "roana_ios_orientation" "$IOS_DIR/Roana/Camera/CameraPreviewView.swift"
grep -q "CameraFrameOrientation.current" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "CameraFrameOrientation.current" "$IOS_DIR/Roana/Camera/CameraPreviewView.swift"
grep -q "visionOrientationName" "$IOS_DIR/Roana/Camera/CameraFrameOrientation.swift"
grep -q "CameraFrameOrientation.swift in Sources" "$PROJECT"
grep -q "DepthAnythingRunner()" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "corridorPipeline.process" "$IOS_DIR/Roana/Camera/CameraSessionController.swift"
grep -q "VNCoreMLRequest" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "VNRecognizedObjectObservation" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "orientation.cgImageOrientation" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "orientation.cgImageOrientation" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -Fq 'vision=\(orientation.visionOrientationName)' "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -Fq 'vision=\(orientation.visionOrientationName)' "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "AVSpeechSynthesizer" "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
grep -q "AVAudioSession.sharedInstance" "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift"
grep -q "#if os(iOS)" "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift"
grep -q "category=portable_smoke" "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift"
grep -q "mode: .spokenAudio" "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift"
grep -q "options: \\[.duckOthers\\]" "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift"
grep -q "SpeechAudioSession.swift in Sources" "$PROJECT"
grep -q "roana_ios_audio_session" "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift"
grep -q "SpeechAudioSession.activate()" "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
grep -q "SpeechAudioSession.activate()" "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift"
grep -q "roana_ios_yolo" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "roana_ios_speech" "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
grep -q "YoloSpeechFeedbackPolicy" "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
grep -q "markSpoken(feedback" "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
grep -q "repeat_interval" "$IOS_DIR/Roana/Speech/SpeechFeedbackDispatcher.swift"
grep -q "Person ahead" "$IOS_DIR/Roana/Speech/YoloSpeechFeedbackPolicy.swift"
grep -q "near_obstacle" "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift"
grep -q "frame_loss" "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift"
grep -q "low_confidence" "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift"
grep -q "roana_ios_corridor" "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift"
grep -q "NSLock" "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift"
grep -q "roana_ios_corridor_feedback" "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift"
grep -q "feedbackDispatcher" "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift"
grep -q "MLMultiArray" "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift"
grep -q "CVPixelBuffer" "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift"
grep -q "VNPixelBufferObservation" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "expectedInputWidth = 518" "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift"
grep -q "expectedInputHeight = 392" "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift"
grep -q "roana_ios_depth" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "computeUnits = .all" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "ModelAssetResourceLocator" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "ModelAssetResourceLocator" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "ROANA_IOS_MODEL_ASSETS_DIR" "$IOS_DIR/Roana/Models/ModelAssetResourceLocator.swift"
grep -q "ModelDescriptionLogger.log(prefix: \"roana_ios_depth\"" "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift"
grep -q "ModelDescriptionLogger.log(prefix: \"roana_ios_yolo\"" "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift"
grep -q "status=model_description" "$IOS_DIR/Roana/Models/ModelDescriptionLogger.swift"
grep -q "ModelAssetResourceLocator.swift in Sources" "$PROJECT"
grep -q "ModelDescriptionLogger.swift in Sources" "$PROJECT"
grep -q "ModelAssets in Resources" "$PROJECT"
grep -q "AVAssetReader" "$IOS_DIR/RoanaTests/VideoReplay/main.swift"
grep -q "roana_ios_replay" "$IOS_DIR/RoanaTests/VideoReplay/main.swift"
grep -q "ROANA_IOS_MODEL_ASSETS_DIR" "$ROOT_DIR/scripts/replay-ios-video.sh"
"$ROOT_DIR/scripts/replay-ios-video.sh" --help >/dev/null
grep -q "Do not upload video frames" "$ROOT_DIR/ios/AGENTS.md"
grep -q "Low confidence, missing frames" "$ROOT_DIR/ios/AGENTS.md"
grep -q "scripts/verify-ios-s0-local.sh" "$ROOT_DIR/ios/AGENTS.md"
grep -q "scripts/analyze-ios-log.py" "$ROOT_DIR/ios/AGENTS.md"

swiftc \
  -D DEBUG \
  "$IOS_DIR/Roana/Models/ModelInferenceMode.swift" \
  "$IOS_DIR/RoanaTests/ModelMode/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" >/dev/null

swiftc \
  "$IOS_DIR/Roana/Models/ModelAssetResourceLocator.swift" \
  "$IOS_DIR/RoanaTests/ModelAssets/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" >/dev/null

swiftc \
  "$IOS_DIR/Roana/Speech/YoloSpeechFeedbackPolicy.swift" \
  "$IOS_DIR/RoanaTests/Speech/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" >/dev/null

swiftc \
  "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorGridFusion.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift" \
  "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift" \
  "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift" \
  "$IOS_DIR/RoanaTests/main.swift" \
  -o "$SMOKE_BINARY"
"$SMOKE_BINARY" >/dev/null

swiftc \
  "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorGridFusion.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift" \
  "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift" \
  "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift" \
  "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift" \
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
