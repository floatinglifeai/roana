// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class FrameDiagnostics {
    struct Stats {
        let width: Int
        let height: Int
        let pixelFormat: String
        let intervalMilliseconds: Double?
        let p50Milliseconds: Double?
        let p95Milliseconds: Double?
        let droppedFrames: Int
        let queueBacklog: Int
        let thermalState: String
        let cameraRunSeconds: Double

        var intervalMillisecondsText: String {
            format(intervalMilliseconds)
        }

        var p50MillisecondsText: String {
            format(p50Milliseconds)
        }

        var p95MillisecondsText: String {
            format(p95Milliseconds)
        }

        var logLine: String {
            "roana_ios_frame_stats " +
                "width=\(width) height=\(height) pixel_format=\(pixelFormat) " +
                "interval_ms=\(intervalMillisecondsText) p50_ms=\(p50MillisecondsText) " +
                "p95_ms=\(p95MillisecondsText) dropped=\(droppedFrames) " +
                "backlog=\(queueBacklog) thermal=\(thermalState) run_s=\(format(cameraRunSeconds))"
        }

        private func format(_ value: Double?) -> String {
            guard let value else {
                return "none"
            }
            return String(format: "%.2f", value)
        }
    }

    private let lock = NSLock()
    private var lastPresentationTime: CMTime?
    private var intervals = RollingPercentileWindow(capacity: 120)
    private var droppedFrameCount = 0
    private var inCallback = false
    private var firstFrameUptime: TimeInterval?

    func record(sampleBuffer: CMSampleBuffer) -> Stats? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        lock.lock()
        defer {
            inCallback = false
            lock.unlock()
        }

        let backlog = inCallback ? 1 : 0
        inCallback = true

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let intervalMilliseconds = intervalSinceLastFrame(presentationTime)
        if let intervalMilliseconds {
            intervals.append(intervalMilliseconds)
        }

        lastPresentationTime = presentationTime

        return makeStats(
            pixelBuffer: pixelBuffer,
            intervalMilliseconds: intervalMilliseconds,
            queueBacklog: backlog,
        )
    }

    func recordDroppedFrame(sampleBuffer: CMSampleBuffer) -> Stats {
        lock.lock()
        defer {
            lock.unlock()
        }

        droppedFrameCount += 1

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            return makeStats(
                pixelBuffer: pixelBuffer,
                intervalMilliseconds: nil,
                queueBacklog: 0,
            )
        }

        return Stats(
            width: 0,
            height: 0,
            pixelFormat: "unknown",
            intervalMilliseconds: nil,
            p50Milliseconds: intervals.percentile(0.50),
            p95Milliseconds: intervals.percentile(0.95),
            droppedFrames: droppedFrameCount,
            queueBacklog: 0,
            thermalState: ProcessInfo.processInfo.thermalState.logValue,
            cameraRunSeconds: cameraRunSeconds(),
        )
    }

    private func intervalSinceLastFrame(_ presentationTime: CMTime) -> Double? {
        guard let lastPresentationTime else {
            return nil
        }

        let seconds = CMTimeGetSeconds(presentationTime - lastPresentationTime)
        guard seconds.isFinite, seconds >= 0 else {
            return nil
        }

        return seconds * 1_000.0
    }

    private func makeStats(
        pixelBuffer: CVPixelBuffer,
        intervalMilliseconds: Double?,
        queueBacklog: Int,
    ) -> Stats {
        Stats(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: pixelFormatName(CVPixelBufferGetPixelFormatType(pixelBuffer)),
            intervalMilliseconds: intervalMilliseconds,
            p50Milliseconds: intervals.percentile(0.50),
            p95Milliseconds: intervals.percentile(0.95),
            droppedFrames: droppedFrameCount,
            queueBacklog: queueBacklog,
            thermalState: ProcessInfo.processInfo.thermalState.logValue,
            cameraRunSeconds: cameraRunSeconds(),
        )
    }

    private func cameraRunSeconds() -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        if firstFrameUptime == nil {
            firstFrameUptime = now
        }
        return max(0, now - (firstFrameUptime ?? now))
    }

    private func pixelFormatName(_ format: OSType) -> String {
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            "420YpCbCr8BiPlanarFullRange"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            "420YpCbCr8BiPlanarVideoRange"
        case kCVPixelFormatType_32BGRA:
            "32BGRA"
        default:
            "\(format)"
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
