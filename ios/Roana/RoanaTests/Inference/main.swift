// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

func fail(_ message: String) -> Never {
    fputs("FrameInferenceCoordinatorSmoke failed: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

let coordinator = FrameInferenceCoordinator<Int>()
let started = DispatchSemaphore(value: 0)
let release = DispatchSemaphore(value: 0)
let completed = DispatchSemaphore(value: 0)

let firstAccepted = coordinator.submit(1) { frame in
    expect(frame == 1, "first frame should be processed")
    started.signal()
    _ = release.wait(timeout: .now() + 2.0)
    completed.signal()
}
expect(firstAccepted, "first frame should be accepted")
expect(started.wait(timeout: .now() + 2.0) == .success, "first frame should start")

let secondAccepted = coordinator.submit(2) { _ in
    fail("second frame should be skipped while first is running")
}
expect(!secondAccepted, "second frame should be skipped")

let runningSnapshot = coordinator.snapshot()
expect(runningSnapshot.acceptedFrames == 1, "one frame accepted while running")
expect(runningSnapshot.skippedFrames == 1, "one frame skipped while running")
expect(runningSnapshot.isRunning, "coordinator should report running")

release.signal()
expect(completed.wait(timeout: .now() + 2.0) == .success, "first frame work should complete")
while coordinator.snapshot().isRunning {
    Thread.sleep(forTimeInterval: 0.01)
}

let thirdCompleted = DispatchSemaphore(value: 0)
let thirdAccepted = coordinator.submit(3) { frame in
    expect(frame == 3, "third frame should be processed after first completes")
    thirdCompleted.signal()
}
expect(thirdAccepted, "third frame should be accepted after completion")
expect(thirdCompleted.wait(timeout: .now() + 2.0) == .success, "third frame should complete")

Thread.sleep(forTimeInterval: 0.05)
let finalSnapshot = coordinator.snapshot()
expect(finalSnapshot.acceptedFrames == 2, "two frames accepted")
expect(finalSnapshot.completedFrames == 2, "two frames completed")
expect(finalSnapshot.skippedFrames == 1, "one frame skipped")
expect(!finalSnapshot.isRunning, "coordinator should be idle")

print("FrameInferenceCoordinatorSmoke passed")
