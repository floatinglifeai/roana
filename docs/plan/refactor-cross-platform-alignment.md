---
refactor_scope: cross-platform-alignment
status: DONE
accepted_severities:
  - P1
  - P2
last_verified: 2026-05-31
---

# Refactor Scope: Cross-Platform Alignment

## Status

DONE

## Target

Align Android and iOS around shared Roana behavior contracts without forcing
shared native UI, camera, runtime, or speech implementation code.

Current execution priority is Android-first. iOS code may consume shared
contracts, but this pass stops before running iOS tests.

## Accepted Severities

- P1: source-of-truth gaps that can hide Android/iOS behavior drift.
- P2: target-local maintainability drift where duplicated constants, status
  names, or log vocabulary make future same-concept changes harder.

## Accepted Cleanup Checklist

1. Make the corridor behavior contract explicit and test-gated.
2. Align the app status vocabulary as shared meaning with native renderers.
3. Align Android evidence log vocabulary with the shared runtime concepts.

## Parked Cross-Seam / Future Ideas

- Shared binary code such as Kotlin Multiplatform is parked until parity
  fixtures become insufficient.
- iOS verification is parked for this pass by user instruction; stop after
  Android verification and before iOS tests.
- Visual UI unification is parked. The shared surface is status meaning, not
  shared native layout code.

## Evidence Ladder

- L1: Android unit tests for contract/status/log vocabulary.
- L2: corridor parity fixture regeneration remains deterministic.
- Android build/test verification after all code changes.
- iOS tests are not run in this pass.

## Stop Condition

Stop when all accepted checklist items are implemented, Android verification
passes, owned changes are committed, and the next remaining action is iOS
verification.

## Execution Log

- 2026-05-31: Created scope gate from the accepted architecture review.
- 2026-05-31: Added Android `CorridorContract`, `StatusContract`, and
  `EvidenceLogContract` modules with focused unit tests.
- 2026-05-31: Rewired Android corridor planner, state machine, grid fusion,
  feedback dispatch, status rendering, evidence logging, and parity fixture
  generation through the Android contract modules.
- 2026-05-31: Regenerated `parity/corridor-core.json`; the remaining fixture
  delta is deterministic depth-grid float output from the current generator.
- 2026-05-31: Verified Android with:
  `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ANDROID_HOME=/opt/homebrew/share/android-commandlinetools ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools ./gradlew :app:testDebugUnitTest :app:assembleDebug`
  and `python3 -m unittest scripts/test_generate_corridor_parity_fixtures.py scripts/test_analyze_v0b_log.py`.
- 2026-05-31: Stopped before iOS tests by user instruction.
