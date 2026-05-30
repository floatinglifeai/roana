// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import CoreML
import CoreMedia
import Foundation
import Vision

final class YoloObstacleDetector {
    enum State: Equatable {
        case ready
        case modelMissing
        case failed(String)

        var logValue: String {
            switch self {
            case .ready:
                "ready"
            case .modelMissing:
                "model_missing"
            case .failed:
                "failed"
            }
        }
    }

    struct Detection: Equatable {
        let label: String
        let confidence: Float
        let boundingBox: CGRect

        var centerX: Float {
            Float(boundingBox.midX)
        }

        var centerY: Float {
            Float(boundingBox.midY)
        }

        var width: Float {
            Float(boundingBox.width)
        }

        var height: Float {
            Float(boundingBox.height)
        }

        var scorePercent: Int {
            Int((confidence * 100).rounded())
        }

        var corridorDetection: CorridorDetection {
            CorridorDetection(
                confidence: confidence,
                centerX: centerX,
                centerY: centerY,
                width: width,
                height: height,
            )
        }
    }

    struct Result {
        let state: State
        let inferenceMilliseconds: Double
        let bestDetection: Detection?
    }

    private let minimumConfidence: VNConfidence
    private let request: VNCoreMLRequest?
    private let state: State

    init(
        modelResourceName: String = "YOLO11n",
        minimumConfidence: VNConfidence = 0.45,
    ) {
        self.minimumConfidence = minimumConfidence

        guard let modelURL = Bundle.main.url(forResource: modelResourceName, withExtension: "mlmodelc") ??
            Bundle.main.url(forResource: modelResourceName, withExtension: "mlpackage") else {
            request = nil
            state = .modelMissing
            print("roana_ios_yolo status=model_missing resource=\(modelResourceName)")
            return
        }

        do {
            let model = try MLModel(contentsOf: modelURL)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill
            self.request = request
            state = .ready
            print("roana_ios_yolo status=ready resource=\(modelResourceName)")
        } catch {
            request = nil
            state = .failed(sanitizeYoloLogValue(error.localizedDescription))
            print("roana_ios_yolo status=failed error=\(sanitizeYoloLogValue(error.localizedDescription))")
        }
    }

    func detect(sampleBuffer: CMSampleBuffer) -> Result {
        let started = CFAbsoluteTimeGetCurrent()
        guard let request else {
            return Result(
                state: state,
                inferenceMilliseconds: elapsedMilliseconds(since: started),
                bestDetection: nil,
            )
        }

        do {
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right)
            try handler.perform([request])
            let detection = bestDetection(from: request.results)
            let inferenceMilliseconds = elapsedMilliseconds(since: started)
            logDetectionResult(
                state: .ready,
                inferenceMilliseconds: inferenceMilliseconds,
                detection: detection,
            )
            return Result(
                state: .ready,
                inferenceMilliseconds: inferenceMilliseconds,
                bestDetection: detection,
            )
        } catch {
            let failureState = State.failed(sanitizeYoloLogValue(error.localizedDescription))
            let inferenceMilliseconds = elapsedMilliseconds(since: started)
            print(
                "roana_ios_yolo status=failed elapsed_ms=\(format(inferenceMilliseconds)) " +
                    "error=\(sanitizeYoloLogValue(error.localizedDescription))",
            )
            return Result(
                state: failureState,
                inferenceMilliseconds: inferenceMilliseconds,
                bestDetection: nil,
            )
        }
    }

    private func bestDetection(from observations: [VNObservation]?) -> Detection? {
        observations?
            .compactMap { $0 as? VNRecognizedObjectObservation }
            .compactMap { observation -> Detection? in
                guard let label = observation.labels.first else {
                    return nil
                }
                guard label.confidence >= minimumConfidence else {
                    return nil
                }
                return Detection(
                    label: label.identifier,
                    confidence: label.confidence,
                    boundingBox: observation.boundingBox,
                )
            }
            .max { lhs, rhs in lhs.confidence < rhs.confidence }
    }

    private func logDetectionResult(
        state: State,
        inferenceMilliseconds: Double,
        detection: Detection?,
    ) {
        if let detection {
            print(
                "roana_ios_yolo status=\(state.logValue) elapsed_ms=\(format(inferenceMilliseconds)) " +
                    "label=\(sanitizeYoloLogValue(detection.label)) score=\(format(Double(detection.confidence))) " +
                    "center_x=\(format(Double(detection.centerX))) center_y=\(format(Double(detection.centerY))) " +
                    "width=\(format(Double(detection.width))) height=\(format(Double(detection.height)))",
            )
        } else {
            print(
                "roana_ios_yolo status=\(state.logValue) elapsed_ms=\(format(inferenceMilliseconds)) detection=none",
            )
        }
    }

    private func elapsedMilliseconds(since started: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - started) * 1_000.0
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private func sanitizeYoloLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "\n", with: "_")
}
