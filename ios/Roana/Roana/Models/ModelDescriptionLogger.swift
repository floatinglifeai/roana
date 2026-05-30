// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import CoreML
import Foundation

enum ModelDescriptionLogger {
    static func log(prefix: String, resourceName: String, model: MLModel) {
        let metadata = model.modelDescription.metadata
        let author = sanitized(metadata[.author] as? String ?? "unknown")
        let version = sanitized(metadata[.versionString] as? String ?? "unknown")
        let inputs = describeFeatures(model.modelDescription.inputDescriptionsByName)
        let outputs = describeFeatures(model.modelDescription.outputDescriptionsByName)
        print(
            "\(prefix) status=model_description resource=\(resourceName) " +
                "author=\(author) version=\(version) inputs=\(inputs) outputs=\(outputs)",
        )
    }

    private static func describeFeatures(_ features: [String: MLFeatureDescription]) -> String {
        features
            .keys
            .sorted()
            .map { key in
                guard let feature = features[key] else {
                    return sanitized(key)
                }
                return "\(sanitized(key)):\(describeFeature(feature))"
            }
            .joined(separator: ",")
    }

    private static func describeFeature(_ feature: MLFeatureDescription) -> String {
        switch feature.type {
        case .image:
            if let imageConstraint = feature.imageConstraint {
                return "image_\(imageConstraint.pixelsWide)x\(imageConstraint.pixelsHigh)"
            }
            return "image"
        case .multiArray:
            if let multiArrayConstraint = feature.multiArrayConstraint {
                let shape = multiArrayConstraint.shape.map(\.stringValue).joined(separator: "x")
                return "multiarray_\(shape)_\(multiArrayConstraint.dataType.logValue)"
            }
            return "multiarray"
        case .dictionary:
            return "dictionary"
        case .string:
            return "string"
        case .int64:
            return "int64"
        case .double:
            return "double"
        case .sequence:
            return "sequence"
        case .state:
            return "state"
        case .invalid:
            return "invalid"
        @unknown default:
            return "unknown"
        }
    }

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: ",", with: "_")
    }
}

private extension MLMultiArrayDataType {
    var logValue: String {
        switch self {
        case .double:
            return "double"
        case .float32:
            return "float32"
        case .float16:
            return "float16"
        case .int32:
            return "int32"
        case .int8:
            return "int8"
        @unknown default:
            return "unknown"
        }
    }
}
