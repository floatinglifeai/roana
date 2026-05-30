// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import CoreGraphics
import ImageIO
import Vision

#if canImport(UIKit)
    import UIKit
#endif

#if canImport(UIKit)
enum CameraFrameOrientation {
    static func current(interfaceOrientation: UIInterfaceOrientation?) -> FrameOrientation {
        switch interfaceOrientation {
        case .landscapeLeft:
            FrameOrientation(interfaceName: "landscape_left", rotationAngle: 0, cgImageOrientation: .up)
        case .landscapeRight:
            FrameOrientation(interfaceName: "landscape_right", rotationAngle: 180, cgImageOrientation: .down)
        case .portraitUpsideDown:
            FrameOrientation(interfaceName: "portrait_upside_down", rotationAngle: 270, cgImageOrientation: .left)
        case .portrait, .unknown, .none:
            FrameOrientation(interfaceName: "portrait", rotationAngle: 90, cgImageOrientation: .right)
        @unknown default:
            FrameOrientation(interfaceName: "unknown", rotationAngle: 90, cgImageOrientation: .right)
        }
    }
}
#endif

struct FrameOrientation {
    let interfaceName: String
    let rotationAngle: CGFloat
    let cgImageOrientation: CGImagePropertyOrientation

    var rotationAngleText: String {
        String(Int(rotationAngle))
    }

    var visionOrientationName: String {
        switch cgImageOrientation {
        case .up:
            "up"
        case .upMirrored:
            "up_mirrored"
        case .down:
            "down"
        case .downMirrored:
            "down_mirrored"
        case .left:
            "left"
        case .leftMirrored:
            "left_mirrored"
        case .right:
            "right"
        case .rightMirrored:
            "right_mirrored"
        }
    }
}
