#!/usr/bin/env python3
"""Analyze Roana iOS log evidence for S0/V0a/V0b code gates."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from statistics import mean


GUIDANCE_COMMANDS = frozenset({"LEFT", "STRAIGHT", "RIGHT"})


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "y"}


def rounded(value: float, places: int = 3) -> float:
    return round(value + 0.0, places)


def line_fields(line: str) -> dict[str, str]:
    return {
        match.group(1): match.group(2)
        for match in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*)=([^ ]+)", line)
    }


def numeric_field(fields: dict[str, str], key: str) -> float | None:
    value = fields.get(key)
    if value is None or value == "none":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def parse_log(log_path: Path) -> dict[str, object]:
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()

    frame_stats = []
    depth_ok = []
    corridor_ok = []
    corridor_feedback_spoken = []
    speech_queued = []
    lifecycle_lines = []
    max_backlog = 0
    max_dropped = 0
    p95_values = []

    for line in lines:
        fields = line_fields(line)
        if "roana_ios_frame_stats" in line:
            frame_stats.append(line)
            max_backlog = max(max_backlog, int(numeric_field(fields, "backlog") or 0))
            max_dropped = max(max_dropped, int(numeric_field(fields, "dropped") or 0))
            p95 = numeric_field(fields, "p95_ms")
            if p95 is not None:
                p95_values.append(p95)
        if "roana_ios_depth status=ok" in line:
            depth_ok.append(line)
        if "roana_ios_corridor decision=" in line:
            corridor_ok.append(line)
        if "roana_ios_corridor_feedback status=spoken" in line:
            corridor_feedback_spoken.append(line)
        if "roana_ios_speech status=queued" in line:
            speech_queued.append(line)
        if "roana_ios_lifecycle" in line:
            lifecycle_lines.append(line)

    normal_corridor_feedback = ""
    stop_corridor_feedback = ""
    for line in corridor_feedback_spoken:
        fields = line_fields(line)
        command = fields.get("command", "")
        if command in GUIDANCE_COMMANDS and not normal_corridor_feedback:
            normal_corridor_feedback = line
        if command == "STOP" and fields.get("message") == "stop" and not stop_corridor_feedback:
            stop_corridor_feedback = line

    permission_seen = any("camera_authorization state=" in line for line in lifecycle_lines)
    camera_started = any("camera_started" in line for line in lifecycle_lines)
    camera_background_stop = any("camera_background_stop" in line for line in lifecycle_lines)
    camera_stopped = any("camera_stopped" in line for line in lifecycle_lines)

    yolo_elapsed = [
        value
        for line in lines
        if "roana_ios_yolo status=ready" in line or "roana_ios_yolo status=ok" in line
        for value in [numeric_field(line_fields(line), "elapsed_ms")]
        if value is not None
    ]
    depth_elapsed = [
        value
        for line in depth_ok
        for value in [numeric_field(line_fields(line), "elapsed_ms")]
        if value is not None
    ]

    return {
        "line_count": len(lines),
        "frame_stats_count": len(frame_stats),
        "max_backlog": max_backlog,
        "max_dropped": max_dropped,
        "max_p95_ms": rounded(max(p95_values), 2) if p95_values else 0.0,
        "avg_yolo_ms": rounded(mean(yolo_elapsed), 2) if yolo_elapsed else 0.0,
        "avg_depth_ms": rounded(mean(depth_elapsed), 2) if depth_elapsed else 0.0,
        "yolo_ok_count": len(yolo_elapsed),
        "depth_ok_count": len(depth_ok),
        "corridor_count": len(corridor_ok),
        "speech_queued_count": len(speech_queued),
        "corridor_feedback_spoken_count": len(corridor_feedback_spoken),
        "normal_corridor_feedback": normal_corridor_feedback,
        "stop_corridor_feedback": stop_corridor_feedback,
        "permission_seen": permission_seen,
        "camera_started": camera_started,
        "camera_background_stop": camera_background_stop,
        "camera_stopped": camera_stopped,
    }


def missing_evidence(
    details: dict[str, object],
    *,
    min_frame_stats: int,
    max_backlog: int,
    max_dropped: int,
    require_yolo: bool,
    require_depth: bool,
    require_corridor: bool,
    require_speech: bool,
    require_background_stop: bool,
    require_permission: bool,
) -> list[str]:
    missing: list[str] = []
    if details["frame_stats_count"] < min_frame_stats:
        missing.append(f"frame_stats>={min_frame_stats}")
    if details["max_backlog"] > max_backlog:
        missing.append(f"backlog<={max_backlog}")
    if details["max_dropped"] > max_dropped:
        missing.append(f"dropped<={max_dropped}")
    if require_permission and not details["permission_seen"]:
        missing.append("camera_permission_state")
    if not details["camera_started"]:
        missing.append("camera_started")
    if require_background_stop and not (
        details["camera_background_stop"] or details["camera_stopped"]
    ):
        missing.append("camera_background_stop")
    if require_yolo and details["yolo_ok_count"] < 1:
        missing.append("yolo_inference")
    if require_depth and details["depth_ok_count"] < 1:
        missing.append("depth_inference")
    if require_corridor and details["corridor_count"] < 1:
        missing.append("corridor_decision")
    if require_speech and details["speech_queued_count"] < 1:
        missing.append("speech_queued")
    if require_corridor and not details["normal_corridor_feedback"]:
        missing.append("corridor_guidance_feedback")
    if require_corridor and not details["stop_corridor_feedback"]:
        missing.append("corridor_stop_feedback")
    return missing


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--min-frame-stats", default=120, type=int)
    parser.add_argument("--max-backlog", default=0, type=int)
    parser.add_argument("--max-dropped", default=0, type=int)
    parser.add_argument("--require-yolo", default="0")
    parser.add_argument("--require-depth", default="0")
    parser.add_argument("--require-corridor", default="0")
    parser.add_argument("--require-speech", default="0")
    parser.add_argument("--require-background-stop", default="0")
    parser.add_argument("--require-permission", default="1")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    details = parse_log(args.log)
    missing = missing_evidence(
        details,
        min_frame_stats=args.min_frame_stats,
        max_backlog=args.max_backlog,
        max_dropped=args.max_dropped,
        require_yolo=parse_bool(args.require_yolo),
        require_depth=parse_bool(args.require_depth),
        require_corridor=parse_bool(args.require_corridor),
        require_speech=parse_bool(args.require_speech),
        require_background_stop=parse_bool(args.require_background_stop),
        require_permission=parse_bool(args.require_permission),
    )
    status = "passed" if not missing else "blocked"
    print(
        json.dumps(
            {
                "status": status,
                "missing": missing,
                "details": details,
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
