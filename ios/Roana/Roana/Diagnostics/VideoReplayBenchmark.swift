// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

#if DEBUG
import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import SwiftUI

struct VideoReplayBenchmarkOptions {
    let requestedVideo: String
    let fps: Double
    let maxSeconds: Double?
    let orientation: FrameOrientation

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> VideoReplayBenchmarkOptions? {
        guard let requestedVideo = value(after: "--roana-replay-video", in: arguments) ??
            environment["ROANA_IOS_REPLAY_VIDEO"]
        else {
            return nil
        }

        let fps = positiveDouble(value(after: "--roana-replay-fps", in: arguments)) ??
            positiveDouble(environment["ROANA_IOS_REPLAY_FPS"]) ??
            10.0
        let maxSeconds = positiveDouble(value(after: "--roana-replay-max-seconds", in: arguments)) ??
            positiveDouble(environment["ROANA_IOS_REPLAY_MAX_SECONDS"])
        let orientation = orientationFromArgument(
            value(after: "--roana-replay-vision-orientation", in: arguments) ??
                environment["ROANA_IOS_REPLAY_VISION_ORIENTATION"] ??
                "right",
        )

        return VideoReplayBenchmarkOptions(
            requestedVideo: requestedVideo,
            fps: fps,
            maxSeconds: maxSeconds,
            orientation: orientation,
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func positiveDouble(_ value: String?) -> Double? {
        guard let value, let parsed = Double(value), parsed > 0 else {
            return nil
        }
        return parsed
    }

    private static func orientationFromArgument(_ value: String) -> FrameOrientation {
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
            FrameOrientation(interfaceName: "portrait", rotationAngle: 90, cgImageOrientation: .right)
        }
    }
}

struct VideoReplayBenchmarkView: View {
    let options: VideoReplayBenchmarkOptions

    @State private var statusText = "Preparing replay"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .font(.headline)
            Text(options.requestedVideo)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .foregroundStyle(.white)
        .task {
            await runReplay()
        }
    }

    private func runReplay() async {
        await MainActor.run {
            statusText = "Replay running"
        }
        let runner = VideoReplayBenchmarkRunner(options: options)
        do {
            try await runner.replay()
            await MainActor.run {
                statusText = "Replay finished"
            }
            await exitAfterFlush(status: 0)
        } catch {
            print("roana_ios_replay status=failed error=\(sanitizeReplayValue(error.localizedDescription))")
            await MainActor.run {
                statusText = "Replay failed"
            }
            await exitAfterFlush(status: 1)
        }
    }

    private func exitAfterFlush(status: Int32) async {
        print("roana_ios_replay status=exiting code=\(status)")
        fflush(stdout)
        fflush(stderr)
        try? await Task.sleep(nanoseconds: 250_000_000)
        Darwin.exit(status)
    }
}

final class VideoReplayBenchmarkRunner {
    private let options: VideoReplayBenchmarkOptions

    init(options: VideoReplayBenchmarkOptions) {
        self.options = options
    }

    func replay() async throws {
        let videoURL = try resolveVideoURL(options.requestedVideo)
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoReplayBenchmarkError.videoTrackMissing
        }

        let durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
        let naturalSize = try await videoTrack.load(.naturalSize)
        let diagnostics = DeviceDiagnostics.current()
        print(
            "roana_ios_lifecycle device_stats model=\(sanitizeReplayValue(diagnostics.deviceModel)) " +
                "ios=\(sanitizeReplayValue(diagnostics.systemVersion)) " +
                "launch_s=\(format(diagnostics.launchUptimeSeconds)) " +
                "thermal=\(sanitizeReplayValue(diagnostics.thermalState)) auth=replay",
        )
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
        let motionQuality = MotionQualityClassifier.classify(nil)
        print(
            "roana_ios_motion_quality label=\(motionQuality.label.rawValue) " +
                "reason=\(motionQuality.reason) trusts_guidance=\(motionQuality.trustsGuidance) " +
                "source=replay",
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
            throw VideoReplayBenchmarkError.videoOutputRejected
        }
        reader.add(output)

        let yolo = YoloObstacleDetector()
        let depth = DepthAnythingRunner()
        var utteranceID = 0
        let feedback = CorridorFeedbackDispatcher(
            speaker: { message, _, utteranceId in
                guard SpeechAudioSession.activate() else {
                    print(
                        "roana_ios_corridor_feedback_audio status=suppressed " +
                            "reason=audio_session_failed id=\(utteranceId)",
                    )
                    return
                }
                print(
                    "roana_ios_corridor_feedback_audio status=queued id=\(utteranceId) " +
                        "message=\(sanitizeReplayValue(message))",
                )
            },
            utteranceIdFactory: {
                utteranceID += 1
                return "roana-ios-device-replay-\(utteranceID)"
            },
        )
        let corridor = CorridorPipeline(feedbackDispatcher: feedback)

        guard reader.startReading() else {
            throw VideoReplayBenchmarkError.readerFailed(reader.error?.localizedDescription ?? "start_failed")
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
            let frameStarted = CFAbsoluteTimeGetCurrent()
            let intervalMilliseconds = lastProcessedTime.map { (presentationSeconds - $0) * 1_000.0 }
            if let intervalMilliseconds {
                intervals.append(intervalMilliseconds)
            }
            lastProcessedTime = presentationSeconds
            logFrameStats(
                sampleBuffer: sampleBuffer,
                intervalMilliseconds: intervalMilliseconds,
                intervals: intervals,
                runSeconds: presentationSeconds,
            )

            let yoloResult = yolo.detect(sampleBuffer: sampleBuffer, orientation: options.orientation)
            let detections = yoloResult.bestDetection.map { [$0.corridorDetection] } ?? []
            let depthResult = depth.infer(sampleBuffer: sampleBuffer, orientation: options.orientation)
            if let grid = depthResult.grid {
                _ = corridor.process(grid: grid, detections: detections)
            } else if depthResult.state != .modelMissing {
                _ = corridor.failSafeStop(reason: "low_confidence")
            }
            print("roana_ios_replay_frame index=\(processed) elapsed_ms=\(format(elapsedMilliseconds(since: frameStarted)))")
        }

        if reader.status == .failed {
            throw VideoReplayBenchmarkError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        print("roana_ios_replay status=finished frames=\(processed)")
    }

    private func resolveVideoURL(_ requestedVideo: String) throws -> URL {
        let requestedURL = URL(fileURLWithPath: requestedVideo)
        if requestedURL.path != requestedVideo || requestedVideo.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: requestedURL.path) {
                return requestedURL
            }
        }

        let requestedPath = requestedVideo as NSString
        let requestedName = requestedPath.lastPathComponent
        let requestedExtension = requestedPath.pathExtension.isEmpty ? "mp4" : requestedPath.pathExtension
        let requestedStem = requestedPath.deletingPathExtension

        if let bundledURL = Bundle.main.url(forResource: requestedStem, withExtension: requestedExtension) {
            return bundledURL
        }

        for directory in replaySearchDirectories() {
            let directURL = directory.appendingPathComponent(requestedName)
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }

            let nestedURL = directory
                .appendingPathComponent("replay", isDirectory: true)
                .appendingPathComponent(requestedName)
            if FileManager.default.fileExists(atPath: nestedURL.path) {
                return nestedURL
            }
        }

        throw VideoReplayBenchmarkError.videoMissing(requestedVideo)
    }

    private func replaySearchDirectories() -> [URL] {
        var directories: [URL] = [
            FileManager.default.temporaryDirectory,
        ]
        for directory in [
            FileManager.SearchPathDirectory.documentDirectory,
            .cachesDirectory,
            .libraryDirectory,
        ] {
            directories.append(contentsOf: FileManager.default.urls(for: directory, in: .userDomainMask))
        }
        return directories
    }

    private func logFrameStats(
        sampleBuffer: CMSampleBuffer,
        intervalMilliseconds: Double?,
        intervals: [Double],
        runSeconds: Double,
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        print(
            "roana_ios_frame_stats width=\(CVPixelBufferGetWidth(pixelBuffer)) " +
                "height=\(CVPixelBufferGetHeight(pixelBuffer)) " +
                "pixel_format=420YpCbCr8BiPlanarFullRange " +
                "interval_ms=\(formatOptional(intervalMilliseconds)) " +
                "p50_ms=\(formatOptional(percentile(intervals, 0.50))) " +
                "p95_ms=\(formatOptional(percentile(intervals, 0.95))) " +
                "dropped=0 backlog=0 thermal=\(ProcessInfo.processInfo.thermalState.logValue) " +
                "run_s=\(format(runSeconds))",
        )
    }
}

enum VideoReplayBenchmarkError: LocalizedError {
    case videoMissing(String)
    case videoTrackMissing
    case videoOutputRejected
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case let .videoMissing(video):
            "video_missing:\(video)"
        case .videoTrackMissing:
            "video_track_missing"
        case .videoOutputRejected:
            "video_output_rejected"
        case let .readerFailed(reason):
            "reader_failed:\(reason)"
        }
    }
}

private extension ProcessInfo.ThermalState {
    var logValue: String {
        switch self {
        case .nominal:
            "nominal"
        case .fair:
            "fair"
        case .serious:
            "serious"
        case .critical:
            "critical"
        @unknown default:
            "unknown"
        }
    }
}

private func elapsedMilliseconds(since started: CFAbsoluteTime) -> Double {
    (CFAbsoluteTimeGetCurrent() - started) * 1_000.0
}

private func percentile(_ values: [Double], _ percentile: Double) -> Double? {
    guard !values.isEmpty else {
        return nil
    }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * percentile).rounded())))
    return sorted[index]
}

private func formatOptional(_ value: Double?) -> String {
    guard let value else {
        return "none"
    }
    return format(value)
}

private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private func sanitizeReplayValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "\n", with: "_")
}
#endif
