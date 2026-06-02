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
ios/Roana/Roana/Presentation/PresentationFrame+Live.swift   # adapter from live types
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
`detections`, and the state are available), build and publish on the main actor
using the provided adapter (`PresentationFrame+Live.swift`):

```swift
let f = PresentationFrame.from(
    grid: grid,                       // CorridorPlanner.DepthGrid
    detections: detections,           // [YoloObstacleDetector.Detection]
    state: corridorResult.state,      // CorridorState
    frames: frameCount, yoloMs: yoloMs, depthMs: depthMs, gaps: gapCount)
Task { @MainActor in self.presentation = f }
```

The adapter maps the real types verbatim (`DepthGrid.toFloatArray()` / `.cols`,
`CorridorState.command` → `RoanaCommand`, `Detection.confidence` → score). No
hand-mapping needed at the call site.

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

## Parity test (deferred to local — needs the toolchain)

Both fixture harnesses are already path-aware:

- iOS `RoanaTests/Parity/main.swift` is a CommandLine executable that reads its
  fixture relative to CWD (`arguments.dropFirst().first ?? "parity/corridor-core.json"`).
  Add a `presentation-core.json` pass the same way.
- Android tests run with the module dir (`app/`) as CWD (see
  `PrivacyBoundaryTest.kt` reading `src/main/...`), so a test reaches the fixture
  at `../parity/presentation-core.json`.

The test should render the four commands plus a near-obstacle STOP and an
all-safe STRAIGHT and assert the structured descriptor (command → colour / glyph
/ caption / pathTargetCol / telemetry text) equals `presentation-core.json`.
Compare descriptors, not pixels. Left for local because it can't be run / proven
green here.

## What is verified vs. not

- ✅ Render modules + the iOS adapter are written against the **actual** repo
  types (`DepthGrid`, `CorridorState`, `CorridorCommand`, `YoloObstacleDetector.Detection`,
  `CorridorConstants`). SwiftUI views have `#Preview`s.
- ⚠️ Not compiled against the Android/iOS toolchains yet — expect a small build
  pass.
- ⚠️ The two wiring edits above are **not applied** in this PR; apply them
  locally so the build stays green before the compile pass.
