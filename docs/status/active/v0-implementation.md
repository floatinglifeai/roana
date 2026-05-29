# V0 Implementation Active Status

Updated: 2026-05-29.

## Current State

- Active objective: implement `docs/plan/v0-implementation-plan.md` via
  `intuitive-flow`.
- Latest completed slice: Android V0a real-device detection-to-TTS proof.
- Current V0b slice: Depth Anything asset smoke with safe CPU fallback.
- Proven locally:
  - `scripts/check-android-env.sh` passes host requirements.
  - `scripts/build-debug.sh` builds `app/build/outputs/apk/debug/app-debug.apk`.
  - `scripts/verify-v0a-device.sh` passed on Xiaomi `2106118C` / Android 14.
  - Skeleton proof artifact: `logs/v0a-device-20260529T084255Z.log` contains
    `tts_init status=success`, `tts_event`, `camera_bound`, and sustained
    `frame_stats` with `gap_count=0`.
  - TFLite proof artifact: `logs/v0a-device-20260529T090726Z.log` contains
    `camera_bound`, `tts_event`, sustained `frame_stats`, and repeated
    `yolo_inference` lines with no `yolo_error`.
  - Detection-to-TTS proof artifact: `logs/v0a-device-20260529T091205Z.log`
    contains `debug_person_detection_proof`, `message=person_ahead`, sustained
    `frame_stats`, and repeated `yolo_inference` lines with no `yolo_error`.
  - QNN/fallback proof artifact: `logs/v0a-device-20260529T092038Z.log`
    contains `qnn_probe`, `qnn_capabilities`, a QNN delegate creation attempt,
    `reason=qnn_interpreter_failed`, and continued CPU/XNNPACK
    `yolo_inference` with no `yolo_error`.
  - Depth smoke proof artifact: `logs/v0a-device-20260529T093023Z.log`
    contains `qnn_probe precision=fp16`, `htp_fp16=false`,
    `reason=qnn_fp16_unavailable`, and `depth_smoke status=loaded` for the
    `[1,518,518,3] -> [1,518,518,1]` Depth Anything V2 TFLite model.
  - Current device: Xiaomi `2106118C` / `SM8350` (`lahaina`, Snapdragon 888).
    It is useful for fallback proof, but below the V0b Depth Anything
    performance target of Snapdragon 8 Gen 2+.

## Stop Condition

V0a is complete. V0b has verified backend fallback and Depth Anything asset
loading baselines. The full V0b corridor demo is not proven on this device
because FP16 HTP is unavailable and the phone is below the target performance
class.

## Next Agent-Owned Step

Add the 15x15 grid and conservative DFS/state-machine logic behind a small
testable pure-Kotlin surface. Full V0b performance proof still needs a
Snapdragon 8 Gen 2+ class device.

## No-Touch Scope

- Do not start V0b depth, QNN, DFS corridor planning, BLE, outdoor navigation,
  cloud/VLM, or custom training work before V0a is proven.
