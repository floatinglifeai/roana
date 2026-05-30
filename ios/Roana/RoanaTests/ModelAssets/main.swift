// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

func fail(_ message: String) -> Never {
    fputs("ModelAssetLocatorSmoke failed: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

func makeBundle(name: String = UUID().uuidString) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).bundle", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        fail("failed to create test bundle: \(error)")
    }
    return url
}

func createDirectory(_ relativePath: String, in bundleURL: URL) {
    let url = bundleURL.appendingPathComponent(relativePath, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "fixture".write(to: url.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    } catch {
        fail("failed to create \(relativePath): \(error)")
    }
}

func bundle(at url: URL) -> Bundle {
    guard let bundle = Bundle(path: url.path) else {
        fail("failed to open test bundle at \(url.path)")
    }
    return bundle
}

let nestedBundleURL = makeBundle()
createDirectory("ModelAssets/YOLO11n.mlpackage", in: nestedBundleURL)
createDirectory("ModelAssets/DepthAnythingV2Small.mlmodelc", in: nestedBundleURL)
let nestedBundle = bundle(at: nestedBundleURL)

let nestedYoloURL = ModelAssetResourceLocator.modelURL(
    forResource: ModelAssetResourceLocator.yoloResourceName,
    in: nestedBundle,
)
expect(nestedYoloURL?.lastPathComponent == "YOLO11n.mlpackage", "should find nested YOLO mlpackage")
expect(nestedYoloURL?.deletingLastPathComponent().lastPathComponent == "ModelAssets", "YOLO should resolve inside ModelAssets")

let nestedDepthURL = ModelAssetResourceLocator.modelURL(
    forResource: ModelAssetResourceLocator.depthResourceName,
    in: nestedBundle,
)
expect(nestedDepthURL?.lastPathComponent == "DepthAnythingV2Small.mlmodelc", "should find nested depth mlmodelc")
expect(nestedDepthURL?.deletingLastPathComponent().lastPathComponent == "ModelAssets", "depth should resolve inside ModelAssets")

let rootBundleURL = makeBundle()
createDirectory("YOLO11n.mlmodelc", in: rootBundleURL)
createDirectory("DepthAnythingV2Small.mlpackage", in: rootBundleURL)
let rootBundle = bundle(at: rootBundleURL)

let rootYoloURL = ModelAssetResourceLocator.modelURL(
    forResource: ModelAssetResourceLocator.yoloResourceName,
    in: rootBundle,
)
expect(rootYoloURL?.lastPathComponent == "YOLO11n.mlmodelc", "should find root YOLO mlmodelc")
expect(rootYoloURL?.deletingLastPathComponent().lastPathComponent == rootBundleURL.lastPathComponent, "YOLO root lookup should not require ModelAssets")

let rootDepthURL = ModelAssetResourceLocator.modelURL(
    forResource: ModelAssetResourceLocator.depthResourceName,
    in: rootBundle,
)
expect(rootDepthURL?.lastPathComponent == "DepthAnythingV2Small.mlpackage", "should find root depth mlpackage")
expect(rootDepthURL?.deletingLastPathComponent().lastPathComponent == rootBundleURL.lastPathComponent, "depth root lookup should not require ModelAssets")

expect(
    ModelAssetResourceLocator.modelURL(forResource: "MissingModel", in: nestedBundle) == nil,
    "missing model should return nil",
)

print("ModelAssetLocatorSmoke passed")
