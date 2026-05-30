#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios/Roana"
BINARY="$IOS_DIR/.video-replay"
MODEL_ASSETS_DIR="${ROANA_IOS_MODEL_ASSETS_DIR:-$IOS_DIR/Roana/ModelAssets}"

cleanup() {
  rm -f "$BINARY"
}
trap cleanup EXIT

swiftc \
  -parse-as-library \
  "$IOS_DIR/Roana/Camera/CameraFrameOrientation.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorPlanner.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorStateMachine.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorGridFusion.swift" \
  "$IOS_DIR/Roana/Corridor/CorridorPipeline.swift" \
  "$IOS_DIR/Roana/Speech/SpeechAudioSession.swift" \
  "$IOS_DIR/Roana/Speech/CorridorFeedbackDispatcher.swift" \
  "$IOS_DIR/Roana/Models/ModelAssetResourceLocator.swift" \
  "$IOS_DIR/Roana/Models/ModelDescriptionLogger.swift" \
  "$IOS_DIR/Roana/Models/YoloObstacleDetector.swift" \
  "$IOS_DIR/Roana/Depth/DepthAnythingOutputAdapter.swift" \
  "$IOS_DIR/Roana/Depth/DepthAnythingRunner.swift" \
  "$IOS_DIR/Roana/Motion/MotionQuality.swift" \
  "$IOS_DIR/RoanaTests/VideoReplay/main.swift" \
  -o "$BINARY"

ROANA_IOS_MODEL_ASSETS_DIR="$MODEL_ASSETS_DIR" "$BINARY" "$@"
