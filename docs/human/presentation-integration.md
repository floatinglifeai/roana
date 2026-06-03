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

The Android activity keeps the screen awake while it is foregrounded. This keeps
the camera guidance surface and the debug HUD from disappearing during active
testing; normal Android lifecycle stop/destroy still releases camera and TTS
resources when the activity leaves foreground.

Android build and JVM tests are expected to run through the containerized repo
scripts because the host Java may be older than the Android Gradle plugin
requires.

For visual-only review on a phone that cannot run the production depth path,
use:

```bash
scripts/build-debug.sh
scripts/preview-android-presentation-demo.sh
```

The preview mode is debug-only and synthetic: it cycles command states with fake
depth/path data and a fake `person` detection box. Long-press the bottom-right
app corner for 2 seconds to switch into the debug HUD. In the HUD, `CAM`,
`DEPTH`, `PATH`, `BOX`, and `TEL` toggle the camera underlay, depth heatmap,
corridor path, detection boxes, and telemetry. When `CAM` and `DEPTH` are both
enabled, the depth layer is translucent so both can be inspected together.

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
