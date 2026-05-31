# Scripts

This directory intentionally keeps executable project gates at stable
`scripts/<name>` paths. Many docs and active proof logs reference those paths,
so do not reorganize this folder casually. Use this index to find the right
command.

## Android

- `build-debug.sh` - build the main Android debug APK in Docker.
- `install-debug.sh` - install the main Android debug APK on a connected
  Android device.
- `check-android-env.sh` - check Android host prerequisites.
- `verify-v0a-device.sh` - run the Android V0a device/log gate.
- `verify-v0b-device.sh` - run the Android V0b corridor device/log gate.
- `record-v0b-corridor-test.sh` - wrap the final known-corridor proof with
  required test notes.
- `probe-qnn-device.sh` - inspect QNN packaging/device layout.
- `verify-qnn-smoke-device.sh` - run the Android QNN model smoke gate.
- `probe-android-acceleration-libs.py` - inspect acceleration-library metadata.

## LiteRT

- `build-litert-smoke-debug.sh` - build the isolated Android LiteRT smoke APK.
- `verify-litert-smoke-device.sh` - run the LiteRT smoke gate on a device.
- `analyze-litert-smoke-log.py` - classify LiteRT smoke log evidence.
- `compare-litert-qnn-logs.py` - compare LiteRT and QNN timing artifacts.
- `plan-litert-next-checks.py` - suggest next checks from a LiteRT smoke log.
- `prepare-litert-qualcomm-v73-runtime.sh` - stage Qualcomm V73 runtime libs for
  smoke validation.
- `compile-litert-qualcomm-aot.sh` - compile Qualcomm AOT model artifacts.

## iOS

- `verify-ios-s0-local.sh` - run local iOS structural/script gates.
- `check-ios-model-assets.py` - validate the iOS Core ML model contract.
- `install-ios-model-assets.py` - stage local iOS model assets by symlink or
  guarded copy.
- `check-ios-xcodeproj-membership.py` - ensure Swift sources/resources are in
  the Xcode project.
- `run-ios-v0b-physical.py` - build, install, launch, capture, and verify the
  iOS V0b physical gate.
- `capture-ios-device-log.py` - turn raw iOS logs into canonical artifacts and
  verify them.
- `verify-ios-device-log.py` - verify captured iOS physical-run logs.
- `replay-ios-video.sh` - compile and run the local iOS video replay harness.
- `verify-ios-replay-log.py` - verify replay logs.
- `label-ios-replay.py` - generate local replay labels from replay logs/videos.
- `run-ios-replay-bundle.py` - run replay, verification, and labeling together.
- `analyze-ios-log.py` - parse iOS physical/replay log evidence.

## Shared / Parity

- `generate-corridor-parity-fixtures.py` - helper for cross-platform corridor
  parity fixture maintenance.

## Tests

`test_*.py` files are plain Python `unittest` modules. Run one or more with:

```bash
python3 -m unittest scripts/test_analyze_v0b_log.py
python3 -m unittest scripts/test_check_ios_model_assets.py scripts/test_verify_ios_device_log.py
```

