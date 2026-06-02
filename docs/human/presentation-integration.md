# Roana presentation overlay — integration

New files (drop into the repo at these paths):

```
parity/presentation-core.json                         # source of truth
docs/human/presentation-contract.md                   # spec
app/src/main/java/com/roana/app/RoanaPresentation.kt   # contract + frame + ramp
app/src/main/java/com/roana/app/RoanaHudView.kt        # debug HUD (custom View)
app/src/main/java/com/roana/app/RoanaAmbientView.kt    # ambient (custom View)
app/src/main/java/com/roana/app/RoanaPresentationView.kt # container + gesture
ios/Roana/Roana/Presentation/PresentationContract.swift
ios/Roana/Roana/Presentation/DebugHudView.swift
ios/Roana/Roana/Presentation/AmbientView.swift
ios/Roana/Roana/Presentation/PresentationRootView.swift
```

The render modules are self-contained and take a normalized `PresentationFrame`.
Only the two wiring steps below touch existing files. They are written against
the current types and need a compile pass — not yet built against the toolchain.

## Android — `MainActivity.kt`

**1. Mount the overlay instead of the bare PreviewView.** In `setupUi()`, the
camera no longer needs a visible preview by default (CameraX can bind
`ImageAnalysis` without `Preview`). Keep `PreviewView` in the tree but `GONE` if
you still want the debug camera underlay later.

```kotlin
private lateinit var presentationView: RoanaPresentationView
// ...
presentationView = RoanaPresentationView(this)
setContentView(
    FrameLayout(this).apply {
        addView(previewView.apply { visibility = View.GONE }) // underlay, off by default
        addView(presentationView)
        // statusView no longer needed — telemetry lives in the HUD now
    },
)
```

**2. Emit a `PresentationFrame` from the analyzer.** In `TimingAnalyzer`, at the
spot that already calls `onCorridorState(corridorResult.state)` you also have the
depth grid, the detection, and the stats in scope. Add one callback:

```kotlin
// where onCorridorState is invoked inside maybeRunLiveCorridor():
onPresentation(
    PresentationFrame.from(
        grid = depthResult.depthGrid,
        detections = listOfNotNull(lastResult.bestDetection),
        state = corridorResult.state,
        frames = frames,
        yoloMs = lastResult.inferenceMs,
        depthMs = depthResult.inferenceMs,
        gaps = gapCount,
    ),
)
```

Wire the callback in `startCamera()`:

```kotlin
onPresentation = { frame -> runOnUiThread { presentationView.submit(frame) } },
```

(Add `onPresentation: (PresentationFrame) -> Unit` to the `TimingAnalyzer`
constructor alongside the existing `onStats` / `onCorridorState`.)

## iOS — `CameraSessionController.swift` + `ContentView.swift`

**1. Publish a frame.** Add to `CameraSessionController`:

```swift
@Published private(set) var presentation = PresentationFrame()
```

In `runInference`, after the corridor result is computed (where `grid`,
`detections`, and the command are available), map and publish on the main actor:

```swift
let f = PresentationFrame(
    command: roanaCommand(corridorResult.state.command),
    reason: corridorResult.state.sourceDecision.reason,
    depth: grid.toFloatArray(),          // adapt to your DepthGrid accessor
    depthCols: grid.cols,
    detections: detections.map { DetectionBox(label: $0.label, score: $0.score,
        centerX: $0.centerX, centerY: $0.centerY, width: $0.width, height: $0.height) },
    frames: frameCount, yoloMs: yoloMs, depthMs: depthMs, gaps: gapCount)
Task { @MainActor in self.presentation = f }
```

Map your corridor enum to the presentation enum (keeps the render decoupled):

```swift
func roanaCommand(_ c: CorridorPlanner.CorridorCommand) -> RoanaCommand {
    switch c { case .straight: return .straight; case .left: return .left
               case .right: return .right; case .stop: return .stop }
}
```

**2. Render it.** Replace the body of `ContentView` (the camera-feed + diagnostics
panel) with:

```swift
struct ContentView: View {
    @ObservedObject var camera: CameraSessionController
    var body: some View {
        PresentationRootView(frame: camera.presentation)
            .background(Color.black)
            .task { camera.start() }
            .onDisappear { camera.stop() }
            // keep the existing permission overlay if not authorized
    }
}
```

The capture session keeps running for analysis even though `CameraPreviewView`
is no longer shown — that is intended (no bright feed by default).

## Parity test (recommended next)

Add a `presentation` case type to the fixture harness both platforms already run
(`CorridorParityFixtureGenerator.kt` / `RoanaTests/Parity/main.swift`): render the
four commands plus a near-obstacle STOP and an all-safe STRAIGHT, and assert the
structured descriptor (command → colour / glyph / caption / pathTargetCol /
telemetry text) equals `presentation-core.json`. Compare descriptors, not pixels.
