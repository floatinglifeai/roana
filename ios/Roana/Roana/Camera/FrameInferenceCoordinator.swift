// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

final class FrameInferenceCoordinator<Frame> {
    struct Snapshot: Equatable {
        let acceptedFrames: Int
        let completedFrames: Int
        let skippedFrames: Int
        let isRunning: Bool
    }

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var acceptedFrames = 0
    private var completedFrames = 0
    private var skippedFrames = 0
    private var isRunning = false

    init(queueLabel: String = "app.roana.ios.inference") {
        queue = DispatchQueue(label: queueLabel)
    }

    @discardableResult
    func submit(
        _ frame: Frame,
        work: @escaping (Frame) -> Void,
    ) -> Bool {
        let frameID: Int
        lock.lock()
        if isRunning {
            skippedFrames += 1
            let skipped = skippedFrames
            lock.unlock()
            print("roana_ios_inference status=skipped reason=busy skipped=\(skipped)")
            return false
        }

        isRunning = true
        acceptedFrames += 1
        frameID = acceptedFrames
        lock.unlock()

        print("roana_ios_inference status=scheduled frame_id=\(frameID)")
        queue.async { [weak self] in
            defer {
                self?.finish(frameID: frameID)
            }
            work(frame)
        }
        return true
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer {
            lock.unlock()
        }
        return Snapshot(
            acceptedFrames: acceptedFrames,
            completedFrames: completedFrames,
            skippedFrames: skippedFrames,
            isRunning: isRunning,
        )
    }

    private func finish(frameID: Int) {
        lock.lock()
        isRunning = false
        completedFrames += 1
        let completed = completedFrames
        let skipped = skippedFrames
        lock.unlock()
        print("roana_ios_inference status=finished frame_id=\(frameID) completed=\(completed) skipped=\(skipped)")
    }
}
