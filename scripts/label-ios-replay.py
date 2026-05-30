#!/usr/bin/env python3
"""Create a small local label summary from an iOS V0b replay log or video."""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
REPLAY = REPO_ROOT / "scripts/replay-ios-video.sh"
ANALYZER = REPO_ROOT / "scripts/analyze-ios-log.py"
ANALYZER_SPEC = importlib.util.spec_from_file_location("analyze_ios_log", ANALYZER)
assert ANALYZER_SPEC is not None
analyze_ios_log = importlib.util.module_from_spec(ANALYZER_SPEC)
assert ANALYZER_SPEC.loader is not None
ANALYZER_SPEC.loader.exec_module(analyze_ios_log)

COMMAND_LABELS = ("STOP", "STRAIGHT", "LEFT", "RIGHT")
GUIDANCE_COMMANDS = frozenset({"STRAIGHT", "LEFT", "RIGHT"})
TOO_CLOSE_REASONS = frozenset({"near_obstacle"})
OCCLUDED_REASONS = frozenset({"low_confidence", "missing_depth", "depth_missing", "inference_failure"})
MOTION_SCENE_LABELS = frozenset({"pointing_down", "unstable"})


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def safe_stem(path: Path) -> str:
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", path.stem).strip("-")
    return stem or "video"


def default_log_path(video: Path) -> Path:
    return Path("/tmp") / f"roana-ios-replay-{safe_stem(video)}-{timestamp()}.log"


def run_replay(video: Path, *, fps: float, max_seconds: float | None, log_path: Path) -> tuple[int, str]:
    command = [str(REPLAY), str(video), "--fps", f"{fps:g}"]
    if max_seconds is not None:
        command.extend(["--max-seconds", f"{max_seconds:g}"])
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    text = completed.stdout + completed.stderr
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(text, encoding="utf-8")
    return completed.returncode, text


def replay_marker_missing(text: str) -> list[str]:
    missing = []
    if "roana_ios_replay status=started" not in text:
        missing.append("replay_started")
    if "roana_ios_replay status=finished" not in text:
        missing.append("replay_finished")
    return missing


def count_evidence(text: str) -> dict[str, Any]:
    decision_counts: Counter[str] = Counter()
    spoken_command_counts: Counter[str] = Counter()
    reason_counts: Counter[str] = Counter()
    motion_labels: Counter[str] = Counter()
    motion_reasons: Counter[str] = Counter()

    for line in text.splitlines():
        fields = analyze_ios_log.line_fields(line)
        if "roana_ios_corridor decision=" in line:
            decision = fields.get("decision", "")
            if decision in COMMAND_LABELS:
                decision_counts[decision] += 1
            reason = fields.get("reason")
            if reason:
                reason_counts[reason] += 1
        if "roana_ios_corridor_feedback status=spoken" in line:
            command = fields.get("command", "")
            if command in COMMAND_LABELS:
                spoken_command_counts[command] += 1
            reason = fields.get("reason")
            if reason:
                reason_counts[reason] += 1
        if "roana_ios_motion_quality" in line:
            label = fields.get("label")
            reason = fields.get("reason")
            if label:
                motion_labels[label] += 1
            if reason:
                motion_reasons[reason] += 1

    command_labels = sorted(set(decision_counts) | set(spoken_command_counts), key=COMMAND_LABELS.index)
    scene_quality_labels = set(motion_labels) & MOTION_SCENE_LABELS
    if set(reason_counts) & TOO_CLOSE_REASONS:
        scene_quality_labels.add("too_close")
    if set(reason_counts) & OCCLUDED_REASONS:
        scene_quality_labels.add("occluded")

    has_guidance = any(command in GUIDANCE_COMMANDS for command in command_labels)
    has_stop = "STOP" in command_labels
    if has_guidance and has_stop:
        fixture_suggestion = "mixed"
    elif has_guidance:
        fixture_suggestion = "guidance"
    elif has_stop:
        fixture_suggestion = "stop"
    else:
        fixture_suggestion = "review"

    return {
        "command_labels": command_labels,
        "scene_quality_labels": sorted(scene_quality_labels),
        "fixture_suggestion": fixture_suggestion,
        "decision_counts": dict(sorted(decision_counts.items())),
        "spoken_command_counts": dict(sorted(spoken_command_counts.items())),
        "reason_counts": dict(sorted(reason_counts.items())),
        "motion_quality_labels": dict(sorted(motion_labels.items())),
        "motion_quality_reasons": dict(sorted(motion_reasons.items())),
    }


def summarize_log(log_path: Path) -> dict[str, Any]:
    text = log_path.read_text(encoding="utf-8", errors="replace")
    missing = replay_marker_missing(text)
    evidence = count_evidence(text)
    if not evidence["command_labels"]:
        missing.append("corridor_command_label")

    details = analyze_ios_log.parse_log(log_path)
    return {
        "status": "passed" if not missing else "blocked",
        "artifact": str(log_path),
        "missing": missing,
        **evidence,
        "metrics": {
            "frame_stats_count": details["frame_stats_count"],
            "max_run_seconds": details["max_run_seconds"],
            "max_p95_ms": details["max_p95_ms"],
            "max_backlog": details["max_backlog"],
            "max_dropped": details["max_dropped"],
            "avg_yolo_ms": details["avg_yolo_ms"],
            "avg_depth_ms": details["avg_depth_ms"],
            "max_thermal_state": details["max_thermal_state"],
        },
    }


def write_json(result: dict[str, Any], *, summary_path: Path | None = None) -> None:
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if summary_path is not None:
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        summary_path.write_text(text, encoding="utf-8")
    sys.stdout.write(text)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", nargs="?", type=Path, help="Local video to replay and label.")
    parser.add_argument("--from-log", type=Path, help="Label an existing replay log instead of running replay.")
    parser.add_argument("--log", type=Path, help="Replay log path to write when labeling a video.")
    parser.add_argument("--summary", type=Path, help="Optional JSON summary path to write.")
    parser.add_argument("--fps", type=float, default=2.0)
    parser.add_argument("--max-seconds", type=float)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if (args.video is None) == (args.from_log is None):
        write_json(
            {
                "status": "failed",
                "artifact": "",
                "missing": ["replay_source"],
                "message": "Provide exactly one local video path or --from-log.",
            },
            summary_path=args.summary,
        )
        return 1

    log_path = args.from_log
    if log_path is None:
        assert args.video is not None
        if not args.video.is_file():
            write_json(
                {
                    "status": "blocked",
                    "artifact": "",
                    "missing": ["video_file"],
                    "message": f"{args.video} does not exist.",
                },
                summary_path=args.summary,
            )
            return 2
        log_path = args.log or default_log_path(args.video)
        replay_status, replay_output = run_replay(
            args.video,
            fps=args.fps,
            max_seconds=args.max_seconds,
            log_path=log_path,
        )
        if replay_status != 0:
            write_json(
                {
                    "status": "failed",
                    "artifact": str(log_path),
                    "missing": ["replay_command"],
                    "message": replay_output,
                },
                summary_path=args.summary,
            )
            return 1

    if not log_path.is_file():
        write_json(
            {
                "status": "blocked",
                "artifact": str(log_path),
                "missing": ["log_file"],
                "message": f"{log_path} does not exist.",
            },
            summary_path=args.summary,
        )
        return 2

    result = summarize_log(log_path)
    write_json(result, summary_path=args.summary)
    return 0 if result["status"] == "passed" else 2


if __name__ == "__main__":
    raise SystemExit(main())
