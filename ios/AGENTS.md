# iOS Agent Contract

This subtree implements the native Swift/SwiftUI iOS port described in
`docs/plan/ios-port-plan.md`. Keep this file aligned with that plan before
expanding iOS work.

## Scope

- Build native Swift/SwiftUI code under `ios/Roana`.
- Use AVFoundation for camera capture, Vision/Core ML for inference, and
  AVSpeechSynthesizer for speech feedback.
- Treat Android Kotlin behavior as the reference for portable decision logic.
  Use `parity/corridor-core.json` and the Swift parity verifier before changing
  corridor planner, grid fusion, state-machine, or feedback behavior.
- Keep model assets out of normal source commits. Stage local `.mlpackage` or
  `.mlmodelc` resources with `scripts/install-ios-model-assets.py`; validate
  them with `scripts/check-ios-model-assets.py --require-present`.

## Safety And Privacy

- Do not upload video frames.
- Do not store camera frames by default.
- Do not add face recognition, identity tracking, cloud VLM calls, or
  street-crossing guidance.
- Low confidence, missing frames, missing depth output, uncertain geometry, or
  inference failure must prefer `STOP`, never `CLEAR`.
- The app is foreground-only for V0-equivalent work. Keep camera work stopped in
  background and keep `UIApplication.isIdleTimerDisabled = true` only while the
  camera view is active.

## Verification

- Run `scripts/verify-ios-s0-local.sh` after iOS code changes. On this current
  host it is expected to pass structural checks and the Xcode build.
- For physical-run evidence, use `scripts/capture-ios-device-log.py` to create
  the canonical `logs/ios-*.log` artifact and run `scripts/verify-ios-device-log.py`
  with the matching gate.
- For V0b physical proof, build/install with a command-line-only
  `DEVELOPMENT_TEAM=...` value, launch `app.roana.ios` with
  `--roana-enable-corridor --roana-debug-fail-safe-stop`, capture logs through
  `scripts/capture-ios-device-log.py --gate v0b`, and do not commit the team ID
  or generated device logs unless explicitly requested.
- Keep shared Xcode schemes aligned with the log gates: `Roana` must stay the
  no-model S0 launch, `Roana-V0a-YOLO` must opt into YOLO only, and
  `Roana-V0b-Corridor` must opt into corridor mode.
- Do not claim physical-device acceptance until a full-Xcode host and real
  iPhone produce log artifacts checked by `scripts/analyze-ios-log.py`.
- Do not claim model performance until real Core ML assets are staged, loaded on
  a physical iPhone, and measured from logs.
- Do not add BLE, Bangle.js haptics, smart-glasses camera source, on-demand VLM,
  App Store release work, or outdoor/crosswalk navigation for the iOS
  V0-equivalent slice.
