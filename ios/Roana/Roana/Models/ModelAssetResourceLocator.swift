// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

enum ModelAssetResourceLocator {
    static let yoloResourceName = "YOLO11n"
    static let depthResourceName = "DepthAnythingV2Small"
    static let bundledSubdirectory = "ModelAssets"
    static let acceptedExtensions = ["mlmodelc", "mlpackage"]
    static let modelAssetsDirectoryEnvironmentKey = "ROANA_IOS_MODEL_ASSETS_DIR"

    static func modelURL(
        forResource resourceName: String,
        in bundle: Bundle = .main,
        modelAssetsDirectory: String? = ProcessInfo.processInfo.environment[modelAssetsDirectoryEnvironmentKey],
    ) -> URL? {
        if let localURL = modelURLInDirectory(forResource: resourceName, rootPath: modelAssetsDirectory) {
            return localURL
        }

        for modelExtension in acceptedExtensions {
            if let rootURL = bundle.url(forResource: resourceName, withExtension: modelExtension) {
                return rootURL
            }
            if let nestedURL = bundle.url(
                forResource: resourceName,
                withExtension: modelExtension,
                subdirectory: bundledSubdirectory,
            ) {
                return nestedURL
            }
        }
        return nil
    }

    private static func modelURLInDirectory(forResource resourceName: String, rootPath: String?) -> URL? {
        guard let rootPath, !rootPath.isEmpty else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        for modelExtension in acceptedExtensions {
            let directURL = rootURL.appendingPathComponent(resourceName).appendingPathExtension(modelExtension)
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }

            let nestedURL = rootURL
                .appendingPathComponent(bundledSubdirectory)
                .appendingPathComponent(resourceName)
                .appendingPathExtension(modelExtension)
            if FileManager.default.fileExists(atPath: nestedURL.path) {
                return nestedURL
            }
        }
        return nil
    }
}
