#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT="${CORRIDOR_TEST_RESULT:-passed}"
NOTES="${CORRIDOR_TEST_NOTES:-}"
RUN_THERMAL_GATE="${RUN_THERMAL_GATE:-0}"
LOG_SECONDS="${LOG_SECONDS:-90}"

usage() {
  cat <<'USAGE'
Usage:
  CORRIDOR_TEST_NOTES="known indoor corridor; blindfolded tester; sighted spotter; no intervention" \
    scripts/record-v0b-corridor-test.sh

Environment:
  CORRIDOR_TEST_RESULT   passed|failed (default: passed)
  CORRIDOR_TEST_NOTES    Required free-form evidence note.
  RUN_THERMAL_GATE       0|1, pass through to verify-v0b-device.sh (default: 0)
  LOG_SECONDS            Short gate logcat duration (default: 90)

The script records the human corridor-test evidence by passing it into the V0b
verifier. Use it only after the known-corridor blindfold run has actually been
performed with a sighted spotter.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

case "$RESULT" in
  passed|failed)
    ;;
  *)
    printf 'error: CORRIDOR_TEST_RESULT must be passed or failed, got %s\n' "$RESULT" >&2
    exit 1
    ;;
esac

if [ -z "$NOTES" ]; then
  printf 'error: CORRIDOR_TEST_NOTES is required so the verifier artifact carries human-test context.\n\n' >&2
  usage >&2
  exit 1
fi

CORRIDOR_TEST_RESULT="$RESULT" \
  CORRIDOR_TEST_NOTES="$NOTES" \
  REQUIRE_CORRIDOR_TEST=1 \
  RUN_THERMAL_GATE="$RUN_THERMAL_GATE" \
  LOG_SECONDS="$LOG_SECONDS" \
  "$ROOT_DIR/scripts/verify-v0b-device.sh"
