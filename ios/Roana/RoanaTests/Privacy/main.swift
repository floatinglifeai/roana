// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

let arguments = CommandLine.arguments.dropFirst()
let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)
let sourceRoot = root.appendingPathComponent("ios/Roana/Roana")
let infoPlist = sourceRoot.appendingPathComponent("Info.plist")

try assertInfoPlistBoundary(infoPlist)
try assertSourceBoundary(sourceRoot)

print("PrivacyBoundary passed")

private func assertInfoPlistBoundary(_ infoPlist: URL) throws {
    let data = try Data(contentsOf: infoPlist)
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    guard let values = plist as? [String: Any] else {
        throw PrivacyBoundaryError.invalidInfoPlist
    }

    let requiredKeys = Set(["NSCameraUsageDescription"])
    let forbiddenKeys = Set([
        "NSPhotoLibraryUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSLocationWhenInUseUsageDescription",
        "NSLocationAlwaysAndWhenInUseUsageDescription",
        "NSBluetoothAlwaysUsageDescription",
        "NSBluetoothPeripheralUsageDescription",
        "NSFaceIDUsageDescription",
        "UIBackgroundModes",
    ])

    let plistKeys = Set(values.keys)
    let missingRequired = requiredKeys.subtracting(plistKeys)
    if !missingRequired.isEmpty {
        throw PrivacyBoundaryError.missingInfoPlistKeys(missingRequired.sorted())
    }

    let presentForbidden = forbiddenKeys.intersection(plistKeys)
    if !presentForbidden.isEmpty {
        throw PrivacyBoundaryError.forbiddenInfoPlistKeys(presentForbidden.sorted())
    }
}

private func assertSourceBoundary(_ sourceRoot: URL) throws {
    let sourceText = try productionSwiftSourceText(sourceRoot)
    try assertForbiddenTokens(
        in: sourceText,
        tokens: [
            "URLSession",
            "HttpURLConnection",
            "NWConnection",
            "NWTCPConnection",
            "NWUDPSession",
            "Socket(",
            "URLRequest(",
            "URL(string:",
            "FileHandle(forWriting",
            "Data.write(",
            ".write(to:",
            "FileManager.default.createFile",
            "UIImageWriteToSavedPhotosAlbum",
            "PHPhotoLibrary",
            "AVAssetWriter",
        ],
        boundary: "network_or_frame_storage",
    )

    try assertForbiddenTokens(
        in: sourceText.lowercased(),
        tokens: [
            "crosswalk",
            "cross street",
            "cross the street",
            "traffic light",
            "outdoor navigation",
            "face recognition",
            "identity",
            "vlm",
            "cloud",
        ],
        boundary: "out_of_scope_guidance_or_identity",
    )
}

private func productionSwiftSourceText(_ sourceRoot: URL) throws -> String {
    guard let enumerator = FileManager.default.enumerator(
        at: sourceRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
    ) else {
        throw PrivacyBoundaryError.unreadableSourceRoot(sourceRoot.path)
    }

    var files: [URL] = []
    for case let file as URL in enumerator {
        guard file.pathExtension == "swift" else {
            continue
        }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey])
        if values.isRegularFile == true {
            files.append(file)
        }
    }

    return try files
        .sorted { $0.path < $1.path }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
}

private func assertForbiddenTokens(
    in sourceText: String,
    tokens: [String],
    boundary: String,
) throws {
    for token in tokens where sourceText.contains(token) {
        throw PrivacyBoundaryError.forbiddenToken(boundary: boundary, token: token)
    }
}

enum PrivacyBoundaryError: Error, CustomStringConvertible {
    case invalidInfoPlist
    case missingInfoPlistKeys([String])
    case forbiddenInfoPlistKeys([String])
    case unreadableSourceRoot(String)
    case forbiddenToken(boundary: String, token: String)

    var description: String {
        switch self {
        case .invalidInfoPlist:
            "Info.plist is not a dictionary"
        case .missingInfoPlistKeys(let keys):
            "Missing required Info.plist keys: \(keys.joined(separator: ","))"
        case .forbiddenInfoPlistKeys(let keys):
            "Forbidden Info.plist keys for iOS V0 privacy boundary: \(keys.joined(separator: ","))"
        case .unreadableSourceRoot(let path):
            "Unreadable source root: \(path)"
        case .forbiddenToken(let boundary, let token):
            "Forbidden \(boundary) token found: \(token)"
        }
    }
}
