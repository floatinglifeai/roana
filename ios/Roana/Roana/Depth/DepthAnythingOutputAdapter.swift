// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import CoreML
import CoreVideo
import Foundation

enum DepthAnythingOutputAdapter {
    static let expectedInputWidth = 518
    static let expectedInputHeight = 392
    static let expectedOutputChannels = 1

    static func plannerGrid(
        values: [Float],
        rows: Int,
        cols: Int,
    ) -> DepthGrid {
        precondition(rows > 0 && cols > 0, "Depth output dimensions must be positive")
        precondition(values.count == rows * cols, "Depth output value count \(values.count) does not match \(rows)x\(cols)")

        if rows < CorridorConstants.gridSize || cols < CorridorConstants.gridSize {
            return DepthGrid.fromDepthMap(values: values, rows: rows, cols: cols)
        }

        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        var sums = Array<Double>(repeating: 0, count: CorridorConstants.gridSize * CorridorConstants.gridSize)
        var counts = Array<Int>(repeating: 0, count: CorridorConstants.gridSize * CorridorConstants.gridSize)

        for row in 0..<rows {
            let gridRow = row * CorridorConstants.gridSize / rows
            for col in 0..<cols {
                let value = values[row * cols + col]
                minimum = min(minimum, value)
                maximum = max(maximum, value)
                let gridCol = col * CorridorConstants.gridSize / cols
                let gridIndex = gridRow * CorridorConstants.gridSize + gridCol
                sums[gridIndex] += Double(value)
                counts[gridIndex] += 1
            }
        }

        let range = maximum - minimum
        let gridValues = sums.indices.map { index -> Float in
            let average = Float(sums[index] / Double(counts[index]))
            return range > 0 ? (average - minimum) / range : 0
        }
        return DepthGrid.square15(gridValues)
    }

    static func plannerGrid(from multiArray: MLMultiArray) throws -> DepthGrid {
        let shape = multiArray.shape.map(\.intValue)
        let dataType = multiArray.dataType
        let parsedShape = try parseDepthShape(shape)
        let values = try extractDepthValues(
            from: multiArray,
            parsedShape: parsedShape,
            dataType: dataType,
        )
        return plannerGrid(values: values, rows: parsedShape.rows, cols: parsedShape.cols)
    }

    static func plannerGrid(from pixelBuffer: CVPixelBuffer) throws -> DepthGrid {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let rows = CVPixelBufferGetHeight(pixelBuffer)
        let cols = CVPixelBufferGetWidth(pixelBuffer)
        guard rows > 0, cols > 0 else {
            throw DepthAdapterError.unsupportedPixelBuffer(width: cols, height: rows, pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer))
        }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DepthAdapterError.missingPixelBufferBaseAddress
        }

        let values = try extractDepthValues(
            from: baseAddress,
            rows: rows,
            cols: cols,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer),
        )
        return plannerGrid(values: values, rows: rows, cols: cols)
    }

    private static func parseDepthShape(_ shape: [Int]) throws -> ParsedDepthShape {
        switch shape {
        case let shape where shape.count == 2:
            return ParsedDepthShape(rows: shape[0], cols: shape[1], channelAxis: nil)
        case let shape where shape.count == 3 && shape[2] == expectedOutputChannels:
            return ParsedDepthShape(rows: shape[0], cols: shape[1], channelAxis: 2)
        case let shape where shape.count == 3 && shape[0] == expectedOutputChannels:
            return ParsedDepthShape(rows: shape[1], cols: shape[2], channelAxis: 0)
        case let shape where shape.count == 4 && shape[0] == 1 && shape[3] == expectedOutputChannels:
            return ParsedDepthShape(rows: shape[1], cols: shape[2], channelAxis: 3)
        case let shape where shape.count == 4 && shape[0] == 1 && shape[1] == expectedOutputChannels:
            return ParsedDepthShape(rows: shape[2], cols: shape[3], channelAxis: 1)
        default:
            throw DepthAdapterError.unsupportedShape(shape)
        }
    }

    private static func extractDepthValues(
        from multiArray: MLMultiArray,
        parsedShape: ParsedDepthShape,
        dataType: MLMultiArrayDataType,
    ) throws -> [Float] {
        let count = parsedShape.rows * parsedShape.cols
        var values = Array<Float>(repeating: 0, count: count)

        switch dataType {
        case .float32:
            try fillFloat32Values(values: &values, multiArray: multiArray, parsedShape: parsedShape)
        case .float16, .double:
            try fillNumberValues(values: &values, multiArray: multiArray, parsedShape: parsedShape)
        default:
            throw DepthAdapterError.unsupportedDataType(dataType)
        }

        return values
    }

    private static func extractDepthValues(
        from baseAddress: UnsafeMutableRawPointer,
        rows: Int,
        cols: Int,
        bytesPerRow: Int,
        pixelFormat: OSType,
    ) throws -> [Float] {
        switch pixelFormat {
        case kCVPixelFormatType_OneComponent16Half,
             kCVPixelFormatType_DepthFloat16,
             kCVPixelFormatType_DisparityFloat16:
            return extractFloat16PixelValues(from: baseAddress, rows: rows, cols: cols, bytesPerRow: bytesPerRow)
        case kCVPixelFormatType_OneComponent32Float,
             kCVPixelFormatType_DepthFloat32,
             kCVPixelFormatType_DisparityFloat32:
            return extractFloat32PixelValues(from: baseAddress, rows: rows, cols: cols, bytesPerRow: bytesPerRow)
        case kCVPixelFormatType_OneComponent8:
            return extractUInt8PixelValues(from: baseAddress, rows: rows, cols: cols, bytesPerRow: bytesPerRow)
        case kCVPixelFormatType_OneComponent16:
            return extractUInt16PixelValues(from: baseAddress, rows: rows, cols: cols, bytesPerRow: bytesPerRow)
        default:
            throw DepthAdapterError.unsupportedPixelBuffer(width: cols, height: rows, pixelFormat: pixelFormat)
        }
    }

    private static func extractFloat16PixelValues(
        from baseAddress: UnsafeMutableRawPointer,
        rows: Int,
        cols: Int,
        bytesPerRow: Int,
    ) -> [Float] {
        var values = Array<Float>(repeating: 0, count: rows * cols)
        for row in 0..<rows {
            let rowPointer = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt16.self)
            for col in 0..<cols {
                values[row * cols + col] = Float(Float16(bitPattern: rowPointer[col]))
            }
        }
        return values
    }

    private static func extractFloat32PixelValues(
        from baseAddress: UnsafeMutableRawPointer,
        rows: Int,
        cols: Int,
        bytesPerRow: Int,
    ) -> [Float] {
        var values = Array<Float>(repeating: 0, count: rows * cols)
        for row in 0..<rows {
            let rowPointer = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Float.self)
            for col in 0..<cols {
                values[row * cols + col] = rowPointer[col]
            }
        }
        return values
    }

    private static func extractUInt8PixelValues(
        from baseAddress: UnsafeMutableRawPointer,
        rows: Int,
        cols: Int,
        bytesPerRow: Int,
    ) -> [Float] {
        var values = Array<Float>(repeating: 0, count: rows * cols)
        for row in 0..<rows {
            let rowPointer = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for col in 0..<cols {
                values[row * cols + col] = Float(rowPointer[col])
            }
        }
        return values
    }

    private static func extractUInt16PixelValues(
        from baseAddress: UnsafeMutableRawPointer,
        rows: Int,
        cols: Int,
        bytesPerRow: Int,
    ) -> [Float] {
        var values = Array<Float>(repeating: 0, count: rows * cols)
        for row in 0..<rows {
            let rowPointer = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt16.self)
            for col in 0..<cols {
                values[row * cols + col] = Float(rowPointer[col])
            }
        }
        return values
    }

    private static func fillFloat32Values(
        values: inout [Float],
        multiArray: MLMultiArray,
        parsedShape: ParsedDepthShape,
    ) throws {
        let pointer = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
        for row in 0..<parsedShape.rows {
            for col in 0..<parsedShape.cols {
                let sourceOffset = try parsedShape.offset(row: row, col: col, strides: multiArray.strides.map(\.intValue))
                values[row * parsedShape.cols + col] = pointer[sourceOffset]
            }
        }
    }

    private static func fillNumberValues(
        values: inout [Float],
        multiArray: MLMultiArray,
        parsedShape: ParsedDepthShape,
    ) throws {
        for row in 0..<parsedShape.rows {
            for col in 0..<parsedShape.cols {
                let index = try parsedShape.index(row: row, col: col)
                values[row * parsedShape.cols + col] = multiArray[index].floatValue
            }
        }
    }
}

enum DepthAdapterError: Error, Equatable {
    case unsupportedShape([Int])
    case unsupportedDataType(MLMultiArrayDataType)
    case missingPixelBufferBaseAddress
    case unsupportedPixelBuffer(width: Int, height: Int, pixelFormat: OSType)
}

private struct ParsedDepthShape {
    let rows: Int
    let cols: Int
    let channelAxis: Int?

    func index(row: Int, col: Int) throws -> [NSNumber] {
        switch channelAxis {
        case nil:
            [NSNumber(value: row), NSNumber(value: col)]
        case 0:
            [0, NSNumber(value: row), NSNumber(value: col)]
        case 1:
            [0, 0, NSNumber(value: row), NSNumber(value: col)]
        case 2:
            [NSNumber(value: row), NSNumber(value: col), 0]
        case 3:
            [0, NSNumber(value: row), NSNumber(value: col), 0]
        default:
            throw DepthAdapterError.unsupportedShape([])
        }
    }

    func offset(row: Int, col: Int, strides: [Int]) throws -> Int {
        let index = try index(row: row, col: col).map(\.intValue)
        return zip(index, strides).reduce(0) { partial, pair in
            partial + pair.0 * pair.1
        }
    }
}
