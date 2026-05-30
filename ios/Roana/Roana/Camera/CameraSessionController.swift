// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation
import CoreVideo
import SwiftUI
import UIKit

final class CameraSessionController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var authorization = CameraAuthorization.current
    @Published private(set) var statusText = "Preparing camera"
    @Published private(set) var latestFrameSummary = "waiting"
    @Published private(set) var deviceDiagnostics = DeviceDiagnostics.current()

    private let sessionQueue = DispatchQueue(label: "app.roana.ios.camera.session")
    private let captureQueue = DispatchQueue(label: "app.roana.ios.camera.frames")
    private let diagnostics = FrameDiagnostics()
    private let obstacleDetector = YoloObstacleDetector()
    private let speechDispatcher = SpeechFeedbackDispatcher()

    private var isConfigured = false
    private var shouldRunWhenForegrounded = false
    private var isInForeground = true

    @MainActor func start() {
        refreshDeviceDiagnostics()
        Task {
            await requestAuthorizationIfNeeded()
            guard authorization.canUseCamera else {
                statusText = "Camera permission required"
                logLifecycle("camera_permission_denied state=\(authorization.logValue)")
                return
            }

            statusText = "Starting camera"
            shouldRunWhenForegrounded = true
            configureAndStartSession()
        }
    }

    @MainActor func stop() {
        shouldRunWhenForegrounded = false
        setIdleTimer(false)
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            if self.session.isRunning {
                self.session.stopRunning()
                self.logLifecycle("camera_stopped")
            }
        }
    }

    @MainActor func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isInForeground = true
            if shouldRunWhenForegrounded, authorization.canUseCamera {
                setIdleTimer(true)
                configureAndStartSession()
            }
        case .inactive, .background:
            isInForeground = false
            setIdleTimer(false)
            sessionQueue.async { [weak self] in
                guard let self else {
                    return
                }
                if self.session.isRunning {
                    self.session.stopRunning()
                    self.logLifecycle("camera_background_stop phase=\(phase)")
                }
            }
        @unknown default:
            isInForeground = false
            setIdleTimer(false)
        }
    }

    @MainActor private func requestAuthorizationIfNeeded() async {
        authorization = .current
        guard authorization.state == .notDetermined else {
            logLifecycle("camera_authorization state=\(authorization.logValue)")
            return
        }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorization = granted ? CameraAuthorization(state: .authorized) : CameraAuthorization(state: .denied)
        logLifecycle("camera_authorization state=\(authorization.logValue)")
    }

    @MainActor private func configureAndStartSession() {
        setIdleTimer(true)
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }

                guard self.shouldRunWhenForegrounded, self.isInForeground else {
                    return
                }

                if !self.session.isRunning {
                    self.session.startRunning()
                    self.logLifecycle("camera_started")
                }

                DispatchQueue.main.async {
                    self.statusText = "Camera active"
                }
            } catch {
                self.logLifecycle("camera_setup_failed error=\(sanitize(error.localizedDescription))")
                DispatchQueue.main.async {
                    self.statusText = "Camera setup failed"
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraSetupError.backCameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraSetupError.inputRejected
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            throw CameraSetupError.outputRejected
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            let angle: CGFloat = 90
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        logLifecycle(
            "camera_configured preset=hd1280x720 pixel_format=420YpCbCr8BiPlanarFullRange discards_late=true queue=serial",
        )
    }

    @MainActor private func refreshDeviceDiagnostics() {
        deviceDiagnostics = .current()
        logLifecycle(
            "device_stats model=\(deviceDiagnostics.deviceModel) ios=\(deviceDiagnostics.systemVersion) " +
                "launch_s=\(String(format: "%.2f", deviceDiagnostics.launchUptimeSeconds)) " +
                "thermal=\(deviceDiagnostics.thermalState) auth=\(authorization.logValue)",
        )
    }

    @MainActor private func updateFrameSummary(_ stats: FrameDiagnostics.Stats) {
        latestFrameSummary = "\(stats.width)x\(stats.height) \(stats.intervalMillisecondsText)ms p95 \(stats.p95MillisecondsText)ms"
        deviceDiagnostics = .current()
    }

    private func setIdleTimer(_ disabled: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }

    private func logLifecycle(_ message: String) {
        print("roana_ios_lifecycle \(message)")
    }
}

extension CameraSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection,
    ) {
        guard let stats = diagnostics.record(sampleBuffer: sampleBuffer) else {
            return
        }

        print(stats.logLine)

        let detectionResult = obstacleDetector.detect(sampleBuffer: sampleBuffer)
        if let detection = detectionResult.bestDetection {
            speechDispatcher.speak(detection: detection)
        }

        Task { @MainActor in
            self.updateFrameSummary(stats)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection,
    ) {
        let stats = diagnostics.recordDroppedFrame(sampleBuffer: sampleBuffer)
        print(stats.logLine)
        Task { @MainActor in
            self.updateFrameSummary(stats)
        }
    }
}

private enum CameraSetupError: Error {
    case backCameraUnavailable
    case inputRejected
    case outputRejected
}

private func sanitize(_ value: String) -> String {
    value.replacingOccurrences(of: " ", with: "_")
}
