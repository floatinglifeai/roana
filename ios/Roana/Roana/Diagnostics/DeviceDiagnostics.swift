// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Darwin
import Foundation
import UIKit

struct DeviceDiagnostics {
    private static let appLaunchUptime = ProcessInfo.processInfo.systemUptime

    let deviceModel: String
    let systemVersion: String
    let launchUptimeSeconds: TimeInterval
    let thermalState: String

    static func current() -> DeviceDiagnostics {
        DeviceDiagnostics(
            deviceModel: hardwareIdentifier(),
            systemVersion: UIDevice.current.systemVersion,
            launchUptimeSeconds: ProcessInfo.processInfo.systemUptime - appLaunchUptime,
            thermalState: ProcessInfo.processInfo.thermalState.logValue,
        )
    }

    private static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)

        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else {
                return
            }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
        return identifier
    }
}

private extension ProcessInfo.ThermalState {
    var logValue: String {
        switch self {
        case .nominal:
            "nominal"
        case .fair:
            "fair"
        case .serious:
            "serious"
        case .critical:
            "critical"
        @unknown default:
            "unknown"
        }
    }
}
