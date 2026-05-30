#!/usr/bin/env python3
"""Validate iOS offline video replay log artifacts for V0b evidence."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ANALYZER = REPO_ROOT / "scripts/analyze-ios-log.py"


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "y"}


def run_command(command: list[str]) -> tuple[int, str]:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    return completed.returncode, completed.stdout + completed.stderr


def analyze_log(args: argparse.Namespace) -> dict[str, object]:
    command = [
        str(ANALYZER),
        "--log",
        str(args.log),
        "--min-frame-stats",
        str(args.min_frame_stats),
        "--min-run-seconds",
        str(args.min_run_seconds),
        "--max-backlog",
        str(args.max_backlog),
        "--max-dropped",
        str(args.max_dropped),
        "--max-p95-ms",
        str(args.max_p95_ms),
        "--max-thermal-state",
        args.max_thermal_state,
        "--max-inference-skipped",
        str(args.max_inference_skipped),
        "--require-yolo",
        "1",
        "--require-yolo-description",
        "1",
        "--require-depth",
        "1",
        "--require-depth-description",
        "1",
        "--require-vision-orientation",
        "1",
        "--require-corridor",
        "1",
        "--require-speech",
        "0",
        "--require-orientation",
        "1",
        "--require-inference",
        "0",
        "--require-fail-safe-stop",
        args.require_fail_safe_stop,
        "--require-background-stop",
        "0",
        "--require-background-cycle",
        "0",
        "--require-idle-timer",
        "0",
        "--require-permission",
        "0",
        "--require-camera-start",
        "0",
        "--require-audio-session",
        args.require_audio_session,
        "--require-corridor-guidance",
        args.require_corridor_guidance,
        "--require-model-mode",
        "corridor",
    ]
    status, output = run_command(command)
    if status != 0:
        return {
            "status": "failed",
            "missing": ["log_analysis"],
            "details": {"output": output},
        }
    return json.loads(output)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--fixture", choices=("stop", "guidance"), default="stop")
    parser.add_argument("--min-frame-stats", default=3, type=int)
    parser.add_argument("--min-run-seconds", default=0.0, type=float)
    parser.add_argument("--max-backlog", default=0, type=int)
    parser.add_argument("--max-dropped", default=0, type=int)
    parser.add_argument("--max-p95-ms", default=0.0, type=float)
    parser.add_argument(
        "--max-thermal-state",
        choices=("none", "nominal", "fair", "serious", "critical"),
        default="nominal",
    )
    parser.add_argument("--max-inference-skipped", default=0, type=int)
    parser.add_argument("--require-audio-session", choices=("0", "1"), default=None)
    parser.add_argument("--require-corridor-guidance", choices=("0", "1"), default=None)
    parser.add_argument("--require-fail-safe-stop", choices=("0", "1"), default="0")
    return parser


def apply_fixture_defaults(args: argparse.Namespace) -> argparse.Namespace:
    if args.require_audio_session is None:
        args.require_audio_session = "1" if args.fixture == "guidance" else "0"
    if args.require_corridor_guidance is None:
        args.require_corridor_guidance = "1" if args.fixture == "guidance" else "0"
    return args


def replay_markers(log_path: Path) -> list[str]:
    text = log_path.read_text(encoding="utf-8", errors="replace")
    missing: list[str] = []
    if "roana_ios_replay status=started" not in text:
        missing.append("replay_started")
    if "roana_ios_replay status=finished" not in text:
        missing.append("replay_finished")
    return missing


def main() -> int:
    args = apply_fixture_defaults(build_parser().parse_args())
    missing: list[str] = []
    analysis = None

    if not args.log.is_file():
        missing.append("log_file")
    else:
        missing.extend(replay_markers(args.log))
        analysis = analyze_log(args)
        missing.extend(analysis.get("missing", []))

    status = "passed" if not missing else "blocked"
    print(
        json.dumps(
            {
                "status": status,
                "fixture": args.fixture,
                "artifact": str(args.log),
                "missing": missing,
                "analysis": analysis,
            },
            indent=2,
            sort_keys=True,
        ),
    )
    return 0 if status == "passed" else 2


if __name__ == "__main__":
    raise SystemExit(main())
