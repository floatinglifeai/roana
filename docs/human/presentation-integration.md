# Roana Presentation Overlay Integration

The presentation overlay is now wired into both native apps. The shared drawing
contract lives in `parity/presentation-core.json`; see
`docs/human/presentation-contract.md` for the product behavior.

## Android

`MainActivity` mounts `RoanaPresentationView` above the camera preview and keeps
the existing bottom status strip for current V0a/V0b evidence. The strip is
offset above the bottom-right gesture zone so the 2-second ambient/debug toggle
remains reachable.

Live corridor frames are converted to `PresentationFrame` inside
`TimingAnalyzer` when depth and corridor processing succeed. Frame-loss,
inference failure, and low-confidence corridor failures publish a STOP
presentation frame so the screen does not keep showing stale guidance after a
safe-stop state.

Android build and JVM tests are expected to run through the containerized repo
scripts because the host Java may be older than the Android Gradle plugin
requires.

## iOS

`CameraSessionController` publishes a `PresentationFrame` and `ContentView`
renders `PresentationRootView` as the primary surface. The camera preview remains
mounted at near-zero opacity so the AVFoundation session and orientation
callbacks continue to work without showing a bright raw camera feed by default.

Successful corridor frames use the live `DepthGrid`, detections, corridor state,
and timing metrics. Depth failure, dropped frames, and debug fail-safe STOP use a
synthetic near-depth STOP frame, matching the fail-safe speech behavior.

The Xcode project includes the `Presentation/**` Swift sources. On Linux,
`scripts/verify-ios-s0-local.sh` runs portable structural checks and exits 2
with build deferred when `swiftc` or full Xcode are unavailable; on macOS with
the Swift/Xcode toolchain it continues into the Swift smoke binaries and
`xcodebuild`.

## Verified In This Pass

- Android debug APK builds with `scripts/build-debug.sh`.
- Android unit tests pass in the Android build container.
- iOS Xcode project source membership passes.
- Linux-runnable iOS Python checks pass, with Swift-only privacy smoke skipped
  when `swiftc` is unavailable.
- `scripts/verify-ios-s0-local.sh` now distinguishes host toolchain absence from
  structural failures.
