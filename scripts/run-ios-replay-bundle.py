#!/usr/bin/env python3
"""Run iOS V0b replay, verification, and labeling into local artifacts."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
REPLAY = REPO_ROOT / "scripts/replay-ios-video.sh"
VERIFIER = REPO_ROOT / "scripts/verify-ios-replay-log.py"
LABELER = REPO_ROOT / "scripts/label-ios-replay.py"


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def safe_stem(path: Path) -> str:
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", path.stem).strip("-")
    return stem or "video"


def run(command: list[str]) -> tuple[int, str]:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    return completed.returncode, completed.stdout + completed.stderr


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_json(text: str) -> dict[str, Any]:
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return {"status": "failed", "missing": ["json_output"], "raw": text}
    return parsed if isinstance(parsed, dict) else {"status": "failed", "missing": ["json_object"], "raw": parsed}


def artifact_paths(video: Path, *, output_dir: Path, requested_timestamp: str) -> dict[str, Path]:
    prefix = f"roana-ios-replay-{safe_stem(video)}-{requested_timestamp}"
    return {
        "log": output_dir / f"{prefix}.log",
        "verify": output_dir / f"{prefix}.verify.json",
        "labels": output_dir / f"{prefix}.labels.json",
    }


def replay_command(args: argparse.Namespace, paths: dict[str, Path]) -> list[str]:
    command = [str(args.replay_bin), str(args.video), "--fps", f"{args.fps:g}"]
    if args.max_seconds is not None:
        command.extend(["--max-seconds", f"{args.max_seconds:g}"])
    return command


def verify_command(args: argparse.Namespace, paths: dict[str, Path]) -> list[str]:
    return [
        str(args.verify_bin),
        "--log",
        str(paths["log"]),
        "--fixture",
        args.resolved_fixture,
        "--min-run-seconds",
        f"{args.min_run_seconds:g}",
        "--max-p95-ms",
        f"{args.max_p95_ms:g}",
    ]


def label_command(args: argparse.Namespace, paths: dict[str, Path]) -> list[str]:
    return [
        str(args.label_bin),
        "--from-log",
        str(paths["log"]),
        "--summary",
        str(paths["labels"]),
    ]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("/tmp"))
    parser.add_argument("--timestamp", default=timestamp())
    parser.add_argument("--fps", type=float, default=2.0)
    parser.add_argument("--max-seconds", type=float)
    parser.add_argument("--fixture", choices=("auto", "stop", "guidance"), default="auto")
    parser.add_argument("--min-run-seconds", type=float, default=0.0)
    parser.add_argument("--max-p95-ms", type=float, default=0.0)
    parser.add_argument("--replay-bin", type=Path, default=REPLAY)
    parser.add_argument("--verify-bin", type=Path, default=VERIFIER)
    parser.add_argument("--label-bin", type=Path, default=LABELER)
    return parser


def resolve_fixture(requested: str, label_json: dict[str, Any]) -> str:
    if requested != "auto":
        return requested
    suggestion = str(label_json.get("fixture_suggestion", ""))
    return "guidance" if suggestion == "guidance" else "stop"


def main() -> int:
    args = build_parser().parse_args()
    paths = artifact_paths(args.video, output_dir=args.output_dir, requested_timestamp=args.timestamp)
    if not args.video.is_file():
        result = {
            "status": "blocked",
            "missing": ["video_file"],
            "artifacts": {name: str(path) for name, path in paths.items()},
            "message": f"{args.video} does not exist.",
        }
        print(json.dumps(result, indent=2, sort_keys=True))
        return 2

    args.output_dir.mkdir(parents=True, exist_ok=True)
    replay_status, replay_output = run(replay_command(args, paths))
    paths["log"].write_text(replay_output, encoding="utf-8")
    if replay_status != 0:
        result = {
            "status": "failed",
            "missing": ["replay_command"],
            "artifacts": {name: str(path) for name, path in paths.items()},
            "details": {"replayStatus": replay_status},
        }
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1

    label_status, label_output = run(label_command(args, paths))
    label_json = parse_json(label_output)
    if not paths["labels"].is_file():
        write_json(paths["labels"], label_json)

    args.resolved_fixture = resolve_fixture(args.fixture, label_json)

    verify_status, verify_output = run(verify_command(args, paths))
    verify_json = parse_json(verify_output)
    write_json(paths["verify"], verify_json)

    missing: list[str] = []
    if verify_status != 0:
        missing.append("replay_verification")
    if label_status != 0:
        missing.append("replay_labels")
    missing.extend(str(item) for item in verify_json.get("missing", []))
    missing.extend(str(item) for item in label_json.get("missing", []))
    missing = sorted(set(missing))

    result = {
        "status": "passed" if not missing else "blocked",
        "missing": missing,
        "artifacts": {name: str(path) for name, path in paths.items()},
        "fixture": args.resolved_fixture,
        "requestedFixture": args.fixture,
        "labels": {
            "fixtureSuggestion": label_json.get("fixture_suggestion"),
            "commandLabels": label_json.get("command_labels", []),
            "sceneQualityLabels": label_json.get("scene_quality_labels", []),
            "segmentCount": len(label_json.get("segments", [])) if isinstance(label_json.get("segments"), list) else 0,
        },
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "passed" else 2


if __name__ == "__main__":
    raise SystemExit(main())
