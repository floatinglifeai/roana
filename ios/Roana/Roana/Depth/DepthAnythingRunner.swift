// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import CoreML
import CoreMedia
import Foundation
import Vision

final class DepthAnythingRunner {
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

    struct Result {
        let state: State
        let inferenceMilliseconds: Double
        let grid: DepthGrid?
    }

    private let request: VNCoreMLRequest?
    private let state: State

    init(modelResourceName: String = ModelAssetResourceLocator.depthResourceName) {
        guard let modelURL = ModelAssetResourceLocator.modelURL(forResource: modelResourceName) else {
            request = nil
            state = .modelMissing
            print("roana_ios_depth status=model_missing resource=\(modelResourceName)")
            return
        }

        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            ModelDescriptionLogger.log(prefix: "roana_ios_depth", resourceName: modelResourceName, model: model)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFill
            self.request = request
            state = .ready
            print("roana_ios_depth status=ready resource=\(modelResourceName) compute_units=all")
        } catch {
            request = nil
            state = .failed(sanitizeDepthLogValue(error.localizedDescription))
            print("roana_ios_depth status=failed error=\(sanitizeDepthLogValue(error.localizedDescription))")
        }
    }

    func infer(sampleBuffer: CMSampleBuffer, orientation: FrameOrientation) -> Result {
        let started = CFAbsoluteTimeGetCurrent()
        guard let request else {
            return Result(
                state: state,
                inferenceMilliseconds: elapsedMilliseconds(since: started),
                grid: nil,
            )
        }

        do {
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation.cgImageOrientation)
            try handler.perform([request])
            let grid = try plannerGrid(from: request.results)
            let inferenceMilliseconds = elapsedMilliseconds(since: started)
            print(
                "roana_ios_depth status=ok elapsed_ms=\(format(inferenceMilliseconds)) " +
                    "vision=\(orientation.visionOrientationName) grid_rows=\(grid.rows) grid_cols=\(grid.cols)",
            )
            return Result(
                state: .ready,
                inferenceMilliseconds: inferenceMilliseconds,
                grid: grid,
            )
        } catch {
            let inferenceMilliseconds = elapsedMilliseconds(since: started)
            print(
                "roana_ios_depth status=failed elapsed_ms=\(format(inferenceMilliseconds)) " +
                    "error=\(sanitizeDepthLogValue(error.localizedDescription))",
            )
            return Result(
                state: .failed(sanitizeDepthLogValue(error.localizedDescription)),
                inferenceMilliseconds: inferenceMilliseconds,
                grid: nil,
            )
        }
    }

    private func plannerGrid(from observations: [VNObservation]?) throws -> DepthGrid {
        guard let featureObservation = observations?.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first,
              let multiArray = featureObservation.featureValue.multiArrayValue else {
            throw DepthRunnerError.missingDepthMultiArray
        }
        return try DepthAnythingOutputAdapter.plannerGrid(from: multiArray)
    }

    private func elapsedMilliseconds(since started: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - started) * 1_000.0
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

enum DepthRunnerError: Error {
    case missingDepthMultiArray
}

private func sanitizeDepthLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "\n", with: "_")
}
