# Agent Guidance

Roana is a cross-platform assistive-navigation prototype. Keep this file short:
project truth for humans lives in `README.md`, `STATUS.md`, `ARCHITECTURE.md`,
and `docs/human/**`.

## Read First

- `README.md` for orientation.
- `STATUS.md` for current Android, iOS, and LiteRT state.
- `ARCHITECTURE.md` for the platform/runtime map.
- `docs/human/**` for human-readable follow-up notes.
- `ios/AGENTS.md` before editing anything under `ios/`.

Treat `docs/status/active/**`, `docs/plan/**`, and `logs/**` as detailed
planning/evidence surfaces unless a human doc promotes a specific artifact.

## Repo Shape

- `app/` is the native Android app.
- `ios/Roana/` is the native SwiftUI iOS app.
- `litert-smoke/` is the isolated Android LiteRT validation app.
- `scripts/` contains build, replay, log-analysis, and device gates.
- `scripts/README.md` indexes the flat script surface; keep existing command
  paths stable unless you are doing a deliberate migration.
- `parity/` contains cross-platform corridor behavior fixtures.
- `website/` is the static public website deployed by GitHub Actions.

## Safety Rules

- Roana augments the white cane, guide dog, and O&M training; do not frame it as
  a replacement.
- Do not add cloud frame upload, frame storage, identity tracking, face
  recognition, street-crossing guidance, or always-on VLM calls unless the user
  explicitly changes the product boundary.
- Fail-safe behavior should prefer `STOP` for low confidence, frame loss,
  uncertain depth, missing model output, or inference failure.
- Android production inference is QNN-required. Do not reintroduce silent
  CPU/XNNPACK fallback into the production path.
- Keep large model binaries and user-recorded videos out of normal commits.

## Verification

Use focused checks for the surface you changed.

Android:

```bash
scripts/build-debug.sh
scripts/verify-v0a-device.sh
scripts/verify-v0b-device.sh
scripts/verify-qnn-smoke-device.sh
```

iOS:

```bash
scripts/verify-ios-s0-local.sh
scripts/check-ios-model-assets.py
ROANA_IOS_DEVELOPMENT_TEAM=<team-id> scripts/run-ios-v0b-physical.py
```

LiteRT validation:

```bash
scripts/build-litert-smoke-debug.sh
scripts/verify-litert-smoke-device.sh
```

Offline Python script tests are plain `unittest`, for example:

```bash
python3 -m unittest scripts/test_analyze_v0b_log.py
```

## Skill Routing

- Use `$intuitive-doc` for README, `STATUS.md`, `ARCHITECTURE.md`, and
  `docs/human/**` drift.
- Use `$intuitive-init` for this file, nested agent files, MCP/LSP setup, and
  agent-only runbooks.
- Use `$intuitive-reduce-entropy` when the repo feels messy but the best cleanup
  surface is not obvious.
- Use `$intuitive-tests` for test taxonomy, fixture, and verification cleanup.
- Use `$intuitive-refactor` before broad code/module/API cleanup.
