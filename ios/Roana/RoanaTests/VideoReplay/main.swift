// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

struct ReplayOptions {
    let videoPath: String
    let fps: Double
    let maxSeconds: Double?
    let orientation: FrameOrientation
}

func fail(_ message: String) -> Never {
    fputs("VideoReplay failed: \(message)\n", stderr)
    exit(1)
}

func parseOptions(arguments: [String]) -> ReplayOptions {
    var videoPath: String?
    var fps = 10.0
    var maxSeconds: Double?
    var orientation = FrameOrientation(interfaceName: "portrait", rotationAngle: 90, cgImageOrientation: .right)
    var index = 1

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--help", "-h":
            print(
                "Usage: video-replay <video.mp4> [--fps 10] [--max-seconds 30] " +
                    "[--vision-orientation right|up|down|left]",
            )
            exit(0)
        case "--fps":
            index += 1
            guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
                fail("--fps requires a positive number")
            }
            fps = value
        case "--max-seconds":
            index += 1
            guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
                fail("--max-seconds requires a positive number")
            }
            maxSeconds = value
        case "--vision-orientation":
            index += 1
            guard index < arguments.count else {
                fail("--vision-orientation requires a value")
            }
            orientation = orientationFromArgument(arguments[index])
        default:
            if videoPath == nil {
                videoPath = argument
            } else {
                fail("unexpected argument: \(argument)")
            }
        }
        index += 1
    }

    guard let videoPath else {
        fail("missing video path")
    }

    return ReplayOptions(
        videoPath: videoPath,
        fps: fps,
        maxSeconds: maxSeconds,
        orientation: orientation,
    )
}

func orientationFromArgument(_ value: String) -> FrameOrientation {
    switch value {
    case "up":
        FrameOrientation(interfaceName: "landscape_left", rotationAngle: 0, cgImageOrientation: .up)
    case "down":
        FrameOrientation(interfaceName: "landscape_right", rotationAngle: 180, cgImageOrientation: .down)
    case "left":
        FrameOrientation(interfaceName: "portrait_upside_down", rotationAngle: 270, cgImageOrientation: .left)
    case "right":
        FrameOrientation(interfaceName: "portrait", rotationAngle: 90, cgImageOrientation: .right)
    default:
        fail("unsupported vision orientation: \(value)")
    }
}

func replay(_ options: ReplayOptions) async throws {
    let videoURL = URL(fileURLWithPath: options.videoPath)
    let asset = AVURLAsset(url: videoURL)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
        fail("video has no video track")
    }

    let durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
    let naturalSize = try await videoTrack.load(.naturalSize)
    print(
        "roana_ios_replay status=started video=\(sanitizeReplayValue(videoURL.lastPathComponent)) " +
            "duration_s=\(format(durationSeconds)) fps=\(format(options.fps)) " +
            "width=\(Int(naturalSize.width)) height=\(Int(naturalSize.height))",
    )
    print("roana_ios_model_mode value=corridor")
    print(
        "roana_ios_lifecycle camera_output_orientation interface=\(options.orientation.interfaceName) " +
            "angle=\(options.orientation.rotationAngleText) vision=\(options.orientation.visionOrientationName)",
    )
    print(
        "roana_ios_orientation source=preview interface=\(options.orientation.interfaceName) " +
            "angle=\(options.orientation.rotationAngleText) vision=\(options.orientation.visionOrientationName)",
    )

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: videoTrack,
        outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ],
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        fail("cannot add video track output")
    }
    reader.add(output)

    let yolo = YoloObstacleDetector()
    let depth = DepthAnythingRunner()
    var utteranceID = 0
    let feedback = CorridorFeedbackDispatcher(
        speaker: { message, _, utteranceId in
            print(
                "roana_ios_corridor_feedback_audio status=queued id=\(utteranceId) " +
                    "message=\(sanitizeReplayValue(message))",
            )
        },
        utteranceIdFactory: {
            utteranceID += 1
            return "roana-ios-replay-\(utteranceID)"
        },
    )
    let corridor = CorridorPipeline(feedbackDispatcher: feedback)

    guard reader.startReading() else {
        fail("asset reader failed to start")
    }

    let frameInterval = 1.0 / options.fps
    var nextFrameTime = 0.0
    var processed = 0
    var lastProcessedTime: Double?
    var intervals: [Double] = []

    while let sampleBuffer = output.copyNextSampleBuffer() {
        let presentationSeconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard presentationSeconds.isFinite else {
            continue
        }
        if let maxSeconds = options.maxSeconds, presentationSeconds > maxSeconds {
            break
        }
        guard presentationSeconds + 0.000_001 >= nextFrameTime else {
            continue
        }
        nextFrameTime = presentationSeconds + frameInterval

        processed += 1
        let intervalMilliseconds = lastProcessedTime.map { (presentationSeconds - $0) * 1_000.0 }
        if let intervalMilliseconds {
            intervals.append(intervalMilliseconds)
        }
        lastProcessedTime = presentationSeconds
        logFrameStats(sampleBuffer: sampleBuffer, intervalMilliseconds: intervalMilliseconds, intervals: intervals, runSeconds: presentationSeconds)

        let yoloResult = yolo.detect(sampleBuffer: sampleBuffer, orientation: options.orientation)
        let detections = yoloResult.bestDetection.map { [$0.corridorDetection] } ?? []
        let depthResult = depth.infer(sampleBuffer: sampleBuffer, orientation: options.orientation)
        if let grid = depthResult.grid {
            _ = corridor.process(grid: grid, detections: detections)
        } else if depthResult.state != .modelMissing {
            _ = corridor.failSafeStop(reason: "low_confidence")
        }
    }

    if reader.status == .failed, let error = reader.error {
        fail("asset reader failed: \(error.localizedDescription)")
    }

    print("roana_ios_replay status=finished frames=\(processed)")
}

func logFrameStats(
    sampleBuffer: CMSampleBuffer,
    intervalMilliseconds: Double?,
    intervals: [Double],
    runSeconds: Double,
) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        return
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    print(
        "roana_ios_frame_stats width=\(width) height=\(height) " +
            "pixel_format=420YpCbCr8BiPlanarFullRange " +
            "interval_ms=\(formatOptional(intervalMilliseconds)) " +
            "p50_ms=\(formatOptional(percentile(intervals, 0.50))) " +
            "p95_ms=\(formatOptional(percentile(intervals, 0.95))) " +
            "dropped=0 backlog=0 thermal=nominal run_s=\(format(runSeconds))",
    )
}

func percentile(_ values: [Double], _ percentile: Double) -> Double? {
    guard !values.isEmpty else {
        return nil
    }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * percentile).rounded())))
    return sorted[index]
}

func formatOptional(_ value: Double?) -> String {
    guard let value else {
        return "none"
    }
    return format(value)
}

func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

func sanitizeReplayValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "\n", with: "_")
}

@main
struct VideoReplayMain {
    static func main() async {
        let options = parseOptions(arguments: CommandLine.arguments)
        do {
            try await replay(options)
        } catch {
            fail(error.localizedDescription)
        }
    }
}
