// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation
import CoreVideo

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

let pixelBufferAttributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
var halfPixelBuffer: CVPixelBuffer?
let halfCreateStatus = CVPixelBufferCreate(
    nil,
    30,
    30,
    kCVPixelFormatType_OneComponent16Half,
    pixelBufferAttributes,
    &halfPixelBuffer,
)
expect(halfCreateStatus == kCVReturnSuccess, "should create half-float depth pixel buffer")
expect(halfPixelBuffer != nil, "half-float depth pixel buffer should exist")

CVPixelBufferLockBaseAddress(halfPixelBuffer!, [])
for row in 0..<30 {
    let rowPointer = CVPixelBufferGetBaseAddress(halfPixelBuffer!)!
        .advanced(by: row * CVPixelBufferGetBytesPerRow(halfPixelBuffer!))
        .assumingMemoryBound(to: UInt16.self)
    for col in 0..<30 {
        rowPointer[col] = Float16(Float(row * 30 + col)).bitPattern
    }
}
CVPixelBufferUnlockBaseAddress(halfPixelBuffer!, [])

let halfPixelGrid = try DepthAnythingOutputAdapter.plannerGrid(from: halfPixelBuffer!)
zip(halfPixelGrid.toFloatArray(), flattenedGrid.toFloatArray()).enumerated().forEach { index, pair in
    expectClose(pair.0, pair.1, "half-float pixel grid index \(index)")
}

var floatPixelBuffer: CVPixelBuffer?
let floatCreateStatus = CVPixelBufferCreate(
    nil,
    2,
    2,
    kCVPixelFormatType_OneComponent32Float,
    pixelBufferAttributes,
    &floatPixelBuffer,
)
expect(floatCreateStatus == kCVReturnSuccess, "should create float depth pixel buffer")
expect(floatPixelBuffer != nil, "float depth pixel buffer should exist")

CVPixelBufferLockBaseAddress(floatPixelBuffer!, [])
for row in 0..<2 {
    let rowPointer = CVPixelBufferGetBaseAddress(floatPixelBuffer!)!
        .advanced(by: row * CVPixelBufferGetBytesPerRow(floatPixelBuffer!))
        .assumingMemoryBound(to: Float.self)
    for col in 0..<2 {
        rowPointer[col] = Float(row * 2 + col) / 10
    }
}
CVPixelBufferUnlockBaseAddress(floatPixelBuffer!, [])

let floatPixelGrid = try DepthAnythingOutputAdapter.plannerGrid(from: floatPixelBuffer!)
let floatPixelExpected = DepthGrid.fromDepthMap(
    values: [
        0.0, 0.1,
        0.2, 0.3,
    ],
    rows: 2,
    cols: 2,
)
zip(floatPixelGrid.toFloatArray(), floatPixelExpected.toFloatArray()).enumerated().forEach { index, pair in
    expectClose(pair.0, pair.1, "float pixel grid index \(index)")
}

print("DepthAdapterSmoke passed")
