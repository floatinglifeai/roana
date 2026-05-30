// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

func fail(_ message: String) -> Never {
    fputs("ModelModeSmoke failed: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

expect(ModelInferenceMode.resolve(arguments: [], environment: [:]) == .disabled, "default mode")
expect(
    ModelInferenceMode.resolve(arguments: ["--roana-enable-yolo"], environment: [:]) == .yolo,
    "yolo argument mode",
)
expect(
    ModelInferenceMode.resolve(arguments: [], environment: ["ROANA_IOS_MODEL_MODE": "yolo"]) == .yolo,
    "yolo environment mode",
)
expect(
    ModelInferenceMode.resolve(arguments: ["--roana-enable-corridor"], environment: [:]) == .corridor,
    "corridor argument mode",
)
expect(
    ModelInferenceMode.resolve(arguments: [], environment: ["ROANA_IOS_MODEL_MODE": "corridor"]) == .corridor,
    "corridor environment mode",
)
expect(
    ModelInferenceMode.resolve(
        arguments: ["--roana-enable-yolo"],
        environment: ["ROANA_IOS_MODEL_MODE": "corridor"],
    ) == .corridor,
    "corridor should outrank yolo when both are set",
)
expect(ModelInferenceMode.yolo.runsYolo, "yolo should run YOLO")
expect(!ModelInferenceMode.yolo.runsDepth, "yolo should not run depth")
expect(ModelInferenceMode.corridor.runsYolo, "corridor should run YOLO")
expect(ModelInferenceMode.corridor.runsDepth, "corridor should run depth")
expect(!ModelInferenceMode.disabled.runsYolo, "disabled should not run YOLO")
expect(!ModelInferenceMode.disabled.runsDepth, "disabled should not run depth")

print("ModelModeSmoke passed")
