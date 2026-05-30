// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

enum ModelAssetResourceLocator {
    static let yoloResourceName = "YOLO11n"
    static let depthResourceName = "DepthAnythingV2Small"
    static let bundledSubdirectory = "ModelAssets"
    static let acceptedExtensions = ["mlmodelc", "mlpackage"]

    static func modelURL(
        forResource resourceName: String,
        in bundle: Bundle = .main,
    ) -> URL? {
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
}
