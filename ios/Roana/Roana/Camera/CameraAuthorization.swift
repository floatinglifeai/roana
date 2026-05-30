// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation

struct CameraAuthorization: Equatable {
    enum State: Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    let state: State

    static var current: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            CameraAuthorization(state: .notDetermined)
        case .authorized:
            CameraAuthorization(state: .authorized)
        case .denied:
            CameraAuthorization(state: .denied)
        case .restricted:
            CameraAuthorization(state: .restricted)
        @unknown default:
            CameraAuthorization(state: .restricted)
        }
    }

    var canUseCamera: Bool {
        state == .authorized
    }

    var logValue: String {
        switch state {
        case .notDetermined:
            "not_determined"
        case .authorized:
            "authorized"
        case .denied:
            "denied"
        case .restricted:
            "restricted"
        }
    }
}
