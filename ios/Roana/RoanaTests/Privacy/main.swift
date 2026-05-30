// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation
import Darwin

do {
    try runPrivacyBoundary()
    print("PrivacyBoundary passed")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

private func runPrivacyBoundary() throws {
    let arguments = CommandLine.arguments.dropFirst()
    let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)
    let sourceRoot = root.appendingPathComponent("ios/Roana/Roana")
    let infoPlist = sourceRoot.appendingPathComponent("Info.plist")

    try assertInfoPlistBoundary(infoPlist)
    try assertSourceBoundary(sourceRoot)
}

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
    let sourceFiles = try productionSwiftSourceFiles(sourceRoot)
    let networkOrFrameStorageRules = [
        ForbiddenSourceRule(token: "import Network", boundary: "network_or_frame_storage"),
        ForbiddenSourceRule(token: "import WebKit", boundary: "network_or_frame_storage"),
    ] + [
        "URLSession",
        "HttpURLConnection",
        "Network.framework",
        "NWConnection",
        "NWTCPConnection",
        "NWUDPSession",
        "Socket(",
        "URLRequest(",
        "URL(string:",
        "FileHandle(forWriting",
        "Data.write(",
        ".write(to:",
        "FileManager.default.copyItem",
        "FileManager.default.moveItem",
        "FileManager.default.createFile",
        "AVCaptureMovieFileOutput",
        "AVCapturePhotoOutput",
        "UIImageWriteToSavedPhotosAlbum",
        "UISaveVideoAtPathToSavedPhotosAlbum",
        "PHPhotoLibrary",
        "AVAssetWriter",
    ].map { token in ForbiddenSourceRule(token: token, boundary: "network_or_frame_storage") }

    try assertForbiddenTokens(
        in: sourceFiles,
        sourceRoot: sourceRoot,
        rules: networkOrFrameStorageRules,
    )

    try assertForbiddenTokens(
        in: sourceFiles,
        sourceRoot: sourceRoot,
        rules: [
            ForbiddenSourceRule(token: "import Photos", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "import PhotosUI", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "import CoreLocation", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "import MapKit", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "import CoreBluetooth", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "import LocalAuthentication", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "CLLocationManager", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "CBCentralManager", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "LAContext", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "MKMapView", boundary: "out_of_scope_guidance_or_identity"),
            ForbiddenSourceRule(token: "crosswalk", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
            ForbiddenSourceRule(token: "cross street", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
            ForbiddenSourceRule(token: "cross the street", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
            ForbiddenSourceRule(token: "traffic light", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
            ForbiddenSourceRule(token: "outdoor navigation", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
            ForbiddenSourceRule(token: "face recognition", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
            ForbiddenSourceRule(token: "identity", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
            ForbiddenSourceRule(token: "vlm", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
            ForbiddenSourceRule(token: "cloud", boundary: "out_of_scope_guidance_or_identity", caseSensitive: false),
        ],
    )
}

private func productionSwiftSourceFiles(_ sourceRoot: URL) throws -> [SourceFile] {
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
        .map { SourceFile(url: $0, lines: try String(contentsOf: $0, encoding: .utf8).splitLines()) }
}

private func assertForbiddenTokens(
    in sourceFiles: [SourceFile],
    sourceRoot: URL,
    rules: [ForbiddenSourceRule],
) throws {
    for sourceFile in sourceFiles {
        for (lineIndex, line) in sourceFile.lines.enumerated() {
            for rule in rules {
                let haystack = rule.caseSensitive ? line : line.lowercased()
                let needle = rule.caseSensitive ? rule.token : rule.token.lowercased()
                if haystack.contains(needle) {
                    throw PrivacyBoundaryError.forbiddenToken(
                        boundary: rule.boundary,
                        token: rule.token,
                        location: SourceLocation(
                            path: sourceFile.url.relativePath(from: sourceRoot),
                            line: lineIndex + 1,
                        ),
                    )
                }
            }
        }
    }
}

private struct SourceFile {
    let url: URL
    let lines: [String]
}

private struct ForbiddenSourceRule {
    let token: String
    let boundary: String
    let caseSensitive: Bool

    init(token: String, boundary: String, caseSensitive: Bool = true) {
        self.token = token
        self.boundary = boundary
        self.caseSensitive = caseSensitive
    }
}

private struct SourceLocation {
    let path: String
    let line: Int
}

private extension String {
    func splitLines() -> [String] {
        split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

private extension URL {
    func relativePath(from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}

private enum PrivacyBoundaryError: Error, CustomStringConvertible {
    case invalidInfoPlist
    case missingInfoPlistKeys([String])
    case forbiddenInfoPlistKeys([String])
    case unreadableSourceRoot(String)
    case forbiddenToken(boundary: String, token: String, location: SourceLocation)

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
        case .forbiddenToken(let boundary, let token, let location):
            "Forbidden \(boundary) token found: \(token) at \(location.path):\(location.line)"
        }
    }
}
