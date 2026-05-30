// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

func fail(_ message: String) -> Never {
    fputs("DepthAdapterSmoke failed: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

func expectClose(_ actual: Float, _ expected: Float, _ message: String) {
    if abs(actual - expected) > 0.0001 {
        fail("\(message): \(actual) != \(expected)")
    }
}

let smallGrid = DepthAnythingOutputAdapter.plannerGrid(
    values: [
        0.1, 0.2,
        0.3, 0.4,
    ],
    rows: 2,
    cols: 2,
)
let smallExpected = DepthGrid.fromDepthMap(
    values: [
        0.1, 0.2,
        0.3, 0.4,
    ],
    rows: 2,
    cols: 2,
)
expect(smallGrid.toFloatArray() == smallExpected.toFloatArray(), "small output should delegate to DepthGrid downsample")

let largeValues = (0..<(30 * 30)).map(Float.init)
let largeGrid = DepthAnythingOutputAdapter.plannerGrid(values: largeValues, rows: 30, cols: 30)
let flattenedGrid = DepthGrid.fromDepthMap(values: largeValues, rows: 30, cols: 30)
zip(largeGrid.toFloatArray(), flattenedGrid.toFloatArray()).enumerated().forEach { index, pair in
    expectClose(pair.0, pair.1, "large optimized grid index \(index)")
}

let constantGrid = DepthAnythingOutputAdapter.plannerGrid(
    values: Array(repeating: 4.2, count: 30 * 30),
    rows: 30,
    cols: 30,
)
expect(constantGrid.toFloatArray().allSatisfy { $0 == 0 }, "constant depth output should normalize to zero grid")

print("DepthAdapterSmoke passed")
