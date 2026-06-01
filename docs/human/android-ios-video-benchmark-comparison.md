# Android/iOS Fixed Video Benchmark Comparison

This note compares the current full real-device replay runs for
`samples/iphone_0530.mp4`. The main Android and iOS runs replayed the same
video at `10 fps` and processed `886` sampled frames through YOLO, Depth
Anything, and the corridor pipeline. A shorter iOS split probe is included only
to explain where the iOS depth time goes.

## Run Artifacts

| Platform | Device | Runtime path | Result artifact |
| --- | --- | --- | --- |
| Android | Xiaomi `2211133C`, SM8550/kalama | TFLite + QNN HTP | `logs/android-video-replay-iphone_0530-20260531T161819Z.json` |
| iOS | `iPhone18,4`, iOS `26.3.1 (a)` | Core ML + Vision, `computeUnits=.all` | `logs/ios-video-replay-iphone_0530-20260531T234355Z.json` |
| iOS split probe | `iPhone18,4`, iOS `26.3.1 (a)` | Core ML + Vision, `computeUnits=.all` | `logs/ios-video-replay-iphone_0530-20260601T001005Z.json` |
| iOS optimized split probe | `iPhone18,4`, iOS `26.3.1 (a)` | Core ML + Vision, `computeUnits=.all` | `logs/ios-video-replay-iphone_0530-20260601T001836Z.json` |

## Timing Summary

| Metric | Android avg / p50 / p95 / max | iOS avg / p50 / p95 / max | Notes |
| --- | ---: | ---: | --- |
| YOLO model only | `4.73 / 4.28 / 7.44 / 11.08 ms` | Not split yet | Android reports model execution separately. |
| YOLO end-to-end detector | `18.15 / 17.66 / 21.32 / 93.38 ms` | `4.02 / 3.82 / 5.13 / 11.67 ms` | iOS YOLO is much faster on this run. |
| Depth model/request | `53.84 / 53.77 / 55.41 / 57.74 ms` | `62.08 / 62.04 / 65.80 / 76.94 ms` | Android is model-only; iOS currently includes Vision request plus grid conversion. |
| Depth input conversion | `7.67 / 7.99 / 8.38 / 40.36 ms` | Not split in this run | iOS split timing was added after this run. |
| Depth output grid | `7.77 / 8.02 / 10.91 / 33.10 ms` | Not split in this run | iOS split timing was added after this run. |
| Corridor pipeline only | `0.59 / 0.44 / 1.20 / 12.10 ms` | Not split in this run | Both are small compared with model work. |
| Depth + grid + corridor total | `69.91 / 69.94 / 74.48 / 135.86 ms` | `62.08 / 62.04 / 65.80 / 76.94 ms` | Closest current end-to-end comparison; iOS is not slower here. |
| Whole replay frame analysis | `98.21 / 97.73 / 105.95 / 235.62 ms` | `66.95 / 66.63 / 71.40 / 120.95 ms` | Android includes bitmap extraction/sampling path differences. |

## Interpretation

The current evidence does not prove that iPhone depth is slower than Android
depth. The confusing comparison is `Android depth_model_ms=53.84` versus
`iOS avg_depth_ms=62.08`, but those are not the same timing boundary.

Android's `depth_model_ms` is the TFLite interpreter call only. Its end-to-end
depth/corridor path is `69.91 ms` once input conversion, output grid conversion,
and corridor processing are included.

iOS `avg_depth_ms=62.08` was measured around `VNImageRequestHandler.perform`
and `DepthAnythingOutputAdapter.plannerGrid`, so it already includes request
handling and output-to-grid conversion. On the closest current boundary, iOS
looks faster than Android for depth/corridor on this sample.

## Follow-Up Measurement

The iOS depth runner now logs additive split fields:

- `vision_request_ms`
- `grid_ms`
- `overhead_ms`

On future physical iPhone runs, `scripts/analyze-ios-log.py` exposes
`avg_depth_vision_request_ms`, `avg_depth_grid_ms`, and
`avg_depth_overhead_ms`. Use those fields to compare iOS Vision/Core ML request
time with Android `depth_model_ms`, and iOS grid time with Android
`depth_grid_ms`.

A short `2 s` iPhone split probe on the same video showed:

| iOS split probe metric | Before direct pixel-buffer grid | After direct pixel-buffer grid |
| --- | ---: | ---: |
| Depth total | `61.20 ms` | `44.14 ms` |
| Vision/Core ML request | `25.17 ms` | `25.22 ms` |
| Output-to-grid conversion | `36.03 ms` | `18.92 ms` |
| Runner overhead | `0.00 ms` | `0.00 ms` |

That points to the iOS output adapter/grid conversion as the main depth-side
hotspot, not Core ML model execution. The first fix removes the full
pixel-buffer-to-`[Float]` copy before grid reduction and roughly halves the
measured grid conversion time in the debug benchmark. Android still spends less
on this phase (`7.77 ms`), so there is room to continue optimizing the Swift
post-processing path.
