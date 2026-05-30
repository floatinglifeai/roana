// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

enum ModelInferenceMode: String {
    case disabled
    case yolo
    case corridor

    static func current() -> ModelInferenceMode {
        #if DEBUG
            let arguments = Set(ProcessInfo.processInfo.arguments)
            let environment = ProcessInfo.processInfo.environment
            return resolve(arguments: arguments, environment: environment)
        #else
        return .disabled
        #endif
    }

    static func resolve(arguments: Set<String>, environment: [String: String]) -> ModelInferenceMode {
        if arguments.contains("--roana-enable-corridor") ||
            environment["ROANA_IOS_MODEL_MODE"] == "corridor" {
            return .corridor
        }
        if arguments.contains("--roana-enable-yolo") ||
            environment["ROANA_IOS_MODEL_MODE"] == "yolo" {
            return .yolo
        }
        return .disabled
    }

    var runsYolo: Bool {
        self == .yolo || self == .corridor
    }

    var runsDepth: Bool {
        self == .corridor
    }
}
