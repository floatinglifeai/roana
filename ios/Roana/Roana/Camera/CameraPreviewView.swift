// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onOrientationChange: (FrameOrientation) -> Void

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.logOrientationUpdates = true
        view.onOrientationChange = onOrientationChange
        return view
    }

    func updateUIView(_ view: PreviewContainerView, context: Context) {
        view.videoPreviewLayer.session = session
        view.onOrientationChange = onOrientationChange
        view.updateOrientation()
    }
}

final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var logOrientationUpdates = false
    var onOrientationChange: ((FrameOrientation) -> Void)?
    private var lastLoggedOrientation = ""
    private var lastReportedOrientation = ""

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = videoPreviewLayer.connection else {
            return
        }

        let orientation = CameraFrameOrientation.current(
            interfaceOrientation: window?.windowScene?.interfaceOrientation,
        )
        if connection.isVideoRotationAngleSupported(orientation.rotationAngle) {
            connection.videoRotationAngle = orientation.rotationAngle
            reportOrientation(orientation)
        }
    }

    private func reportOrientation(_ orientation: FrameOrientation) {
        let key = "\(orientation.interfaceName):\(orientation.rotationAngleText):\(orientation.visionOrientationName)"
        guard key != lastReportedOrientation else {
            return
        }
        lastReportedOrientation = key
        onOrientationChange?(orientation)
        logOrientation(orientation, key: key)
    }

    private func logOrientation(_ orientation: FrameOrientation, key: String) {
        guard logOrientationUpdates, key != lastLoggedOrientation else {
            return
        }

        lastLoggedOrientation = key
        print(
            "roana_ios_orientation source=preview interface=\(orientation.interfaceName) " +
                "angle=\(orientation.rotationAngleText) vision=\(orientation.visionOrientationName)",
        )
    }
}
