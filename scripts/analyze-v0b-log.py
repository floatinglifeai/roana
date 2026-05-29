#!/usr/bin/env python3
"""Summarize V0b verifier log evidence for device-gate decisions."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


TARGET_SOC_MARKERS = (
    "sm8550",
    "sm8650",
    "sm8750",
    "sm8850",
    "mt6989",
    "mt6991",
    "dimensity 9300",
    "dimensity 9400",
)
GUIDANCE_COMMANDS = frozenset({"LEFT", "STRAIGHT", "RIGHT"})
THERMAL_STATUS_LABELS = {
    0: "none",
    1: "light",
    2: "moderate",
    3: "severe",
    4: "critical",
    5: "emergency",
    6: "shutdown",
}
THERMAL_STATUS_VALUES = {label: level for level, label in THERMAL_STATUS_LABELS.items()}
THERMAL_SEVERE_THRESHOLD = 3


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "y"}


def threshold_label(value: float) -> str:
    return str(int(value)) if value.is_integer() else str(value)


def mean(values: list[float]) -> float:
    return sum(values) / len(values)


def rounded(value: float, places: int) -> float:
    return round(value + 0.0, places)


def fps_from_ms(elapsed_ms: float) -> float:
    if elapsed_ms <= 0:
        return 0.0
    return rounded(1000.0 / elapsed_ms, 3)


def first_regex(lines: list[str], required_text: str, pattern: str) -> str:
    regex = re.compile(pattern)
    for line in lines:
        if required_text not in line:
            continue
        match = regex.search(line)
        if match:
            return match.group(1)
    return ""


def line_fields(line: str) -> dict[str, str]:
    return {
        match.group(1): match.group(2)
        for match in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*)=([^ ]+)", line)
    }


def thermal_status_details(value: str) -> dict[str, object]:
    raw_value = value.strip()
    status_token = ""
    for pattern in (
        r"\bThermal Status:\s*([A-Za-z_]+|[0-9]+)",
        r"\bmStatus=([A-Za-z_]+|[0-9]+)",
    ):
        match = re.search(pattern, raw_value, re.IGNORECASE)
        if match:
            status_token = match.group(1)
            break

    level: int | None = None
    if status_token:
        normalized_token = status_token.strip(" ,;").lower()
        if normalized_token.isdigit():
            level = int(normalized_token)
        else:
            level = THERMAL_STATUS_VALUES.get(
                normalized_token.removeprefix("thermal_status_")
            )

    label = THERMAL_STATUS_LABELS.get(level, "") if level is not None else ""
    return {
        "level": level,
        "label": label,
        "severe_or_worse": level is not None and level >= THERMAL_SEVERE_THRESHOLD,
    }


def parse_log(log_path: Path, tail_sample_count: int) -> dict[str, object]:
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()

    live_depth_values: list[float] = []
    live_corridor_count = 0
    for line in lines:
        if "corridor_live status=ok" not in line:
            continue
        live_corridor_count += 1
        match = re.search(r"\bdepth_ms=([0-9.]+)", line)
        if match:
            live_depth_values.append(float(match.group(1)))

    if live_depth_values:
        depth_elapsed_ms = rounded(mean(live_depth_values), 2)
    else:
        depth_elapsed_ms = 0.0
        fallback_elapsed = first_regex(lines, "depth_plan status=ok", r"\belapsed_ms=([0-9.]+)")
        if fallback_elapsed:
            depth_elapsed_ms = rounded(float(fallback_elapsed), 2)

    tail_values = live_depth_values[-tail_sample_count:]
    tail_depth_elapsed_ms = rounded(mean(tail_values), 2) if tail_values else 0.0

    frame_stats_lines = [line for line in lines if "frame_stats" in line]
    gap_count = 0
    if frame_stats_lines:
        gap_match = re.search(r"\bgap_count=([0-9]+)", frame_stats_lines[-1])
        if gap_match:
            gap_count = int(gap_match.group(1))

    corridor_feedback = ""
    normal_corridor_feedback = ""
    safe_stop_feedback = ""
    for line in lines:
        if "corridor_feedback status=spoken" in line:
            fields = line_fields(line)
            if not corridor_feedback:
                corridor_feedback = line
            if (
                fields.get("reason") == "low_confidence" and
                fields.get("command") == "STOP" and
                fields.get("message") == "stop"
            ):
                safe_stop_feedback = line
            elif fields.get("command") in GUIDANCE_COMMANDS and not normal_corridor_feedback:
                normal_corridor_feedback = line

    safe_stop_proof = ""
    for line in lines:
        if "debug_safe_stop_proof enabled=true" in line:
            fields = line_fields(line)
            if (
                fields.get("reason") == "low_confidence" and
                fields.get("decision") == "STOP" and
                fields.get("state") == "STOP"
            ):
                safe_stop_proof = line
                break

    return {
        "fp16_htp": first_regex(lines, "qnn_capabilities", r"\bhtp_fp16=([^ ]+)"),
        "depth_elapsed_ms": depth_elapsed_ms,
        "depth_fps": fps_from_ms(depth_elapsed_ms),
        "corridor_feedback": corridor_feedback,
        "normal_corridor_feedback": normal_corridor_feedback,
        "safe_stop_proof": safe_stop_proof,
        "safe_stop_feedback": safe_stop_feedback,
        "live_corridor_count": live_corridor_count,
        "frame_stats_count": len(frame_stats_lines),
        "gap_count": gap_count,
        "tail_depth_elapsed_ms": tail_depth_elapsed_ms,
        "tail_depth_fps": fps_from_ms(tail_depth_elapsed_ms),
    }


def is_target_soc(soc_model: str, board_platform: str) -> bool:
    device_text = f"{soc_model} {board_platform}".lower()
    return any(marker in device_text for marker in TARGET_SOC_MARKERS)


def add_main_missing(
    missing: list[str],
    details: dict[str, object],
    require_target_soc: bool,
    require_fp16_htp: bool,
    max_depth_ms: float,
    min_depth_fps_label: str,
    min_live_corridor_frames: int,
    min_frame_stats: int,
    require_corridor_feedback: bool,
    require_safe_stop_proof: bool,
) -> None:
    if require_target_soc and not details["target_soc"]:
        missing.append("target_soc")
    if require_fp16_htp and details["fp16_htp"] != "true":
        missing.append("fp16_htp")
    if details["depth_elapsed_ms"] <= 0 or details["depth_elapsed_ms"] > max_depth_ms:
        missing.append(f"depth_fps>={min_depth_fps_label}")
    if details["live_corridor_count"] < min_live_corridor_frames:
        missing.append(f"corridor_live_frames>={min_live_corridor_frames}")
    if details["frame_stats_count"] < min_frame_stats:
        missing.append(f"frame_stats>={min_frame_stats}")
    if details["gap_count"] != 0:
        missing.append("no_frame_gaps")
    if require_corridor_feedback and not details["normal_corridor_feedback"]:
        missing.append("corridor_feedback_spoken")
    if require_safe_stop_proof and not details["safe_stop_proof"]:
        missing.append("debug_safe_stop_proof")
    if require_safe_stop_proof and not details["safe_stop_feedback"]:
        missing.append("safe_stop_feedback")


def add_thermal_missing(
    missing: list[str],
    details: dict[str, object],
    max_depth_ms: float,
    min_depth_fps_label: str,
) -> None:
    thermal_minutes = int(details["thermal_minutes_required"])
    if details["thermal_live_corridor_count"] < thermal_minutes * 60:
        missing.append("thermal_corridor_live_frames")
    if details["thermal_depth_elapsed_ms"] <= 0 or details["thermal_depth_elapsed_ms"] > max_depth_ms:
        missing.append(f"thermal_avg_depth_fps>={min_depth_fps_label}")
    if details["thermal_tail_depth_elapsed_ms"] <= 0 or details["thermal_tail_depth_elapsed_ms"] > max_depth_ms:
        missing.append(f"thermal_tail_depth_fps>={min_depth_fps_label}")
    if details["thermal_frame_stats_count"] < thermal_minutes:
        missing.append("thermal_frame_stats")
    if details["thermal_gap_count"] != 0:
        missing.append("thermal_no_frame_gaps")
    if details["thermal_status_before_severe_or_worse"]:
        missing.append("thermal_status_before_not_severe")
    if details["thermal_status_after_severe_or_worse"]:
        missing.append("thermal_status_after_not_severe")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--thermal-log", type=Path)
    parser.add_argument("--model", default="")
    parser.add_argument("--soc-model", default="")
    parser.add_argument("--board-platform", default="")
    parser.add_argument("--abis", default="")
    parser.add_argument("--min-depth-fps", default=10.0, type=float)
    parser.add_argument("--require-target-soc", default="1")
    parser.add_argument("--require-fp16-htp", default="1")
    parser.add_argument("--min-live-corridor-frames", default=5, type=int)
    parser.add_argument("--min-frame-stats", default=5, type=int)
    parser.add_argument("--require-corridor-feedback", default="1")
    parser.add_argument("--require-safe-stop-proof", default="0")
    parser.add_argument("--thermal-minutes-required", default=30, type=int)
    parser.add_argument("--thermal-status-before", default="")
    parser.add_argument("--thermal-status-after", default="")
    parser.add_argument("--require-corridor-test", default="1")
    parser.add_argument("--corridor-test-result", default="")
    parser.add_argument("--corridor-test-notes", default="")
    parser.add_argument("--tail-sample-count", default=20, type=int)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    max_depth_ms = rounded(1000.0 / args.min_depth_fps, 2)
    min_depth_fps_label = threshold_label(args.min_depth_fps)

    main_log = parse_log(args.log, args.tail_sample_count)
    thermal_log = parse_log(args.thermal_log, args.tail_sample_count) if args.thermal_log else None
    thermal_status_before = thermal_status_details(args.thermal_status_before)
    thermal_status_after = thermal_status_details(args.thermal_status_after)

    details = {
        "model": args.model,
        "soc_model": args.soc_model,
        "board_platform": args.board_platform,
        "abis": args.abis,
        "target_soc": is_target_soc(args.soc_model, args.board_platform),
        "fp16_htp": main_log["fp16_htp"],
        "depth_elapsed_ms": main_log["depth_elapsed_ms"],
        "depth_fps": main_log["depth_fps"],
        "corridor_feedback": main_log["corridor_feedback"],
        "normal_corridor_feedback": main_log["normal_corridor_feedback"],
        "safe_stop_proof": main_log["safe_stop_proof"],
        "safe_stop_feedback": main_log["safe_stop_feedback"],
        "live_corridor_count": main_log["live_corridor_count"],
        "min_depth_fps": args.min_depth_fps,
        "max_depth_ms": max_depth_ms,
        "frame_stats_count": main_log["frame_stats_count"],
        "gap_count": main_log["gap_count"],
        "thermal_minutes_required": args.thermal_minutes_required,
        "thermal_gate_run": thermal_log is not None,
        "thermal_log_path": str(args.thermal_log or ""),
        "thermal_status_before": args.thermal_status_before,
        "thermal_status_before_level": thermal_status_before["level"],
        "thermal_status_before_label": thermal_status_before["label"],
        "thermal_status_before_severe_or_worse": thermal_status_before[
            "severe_or_worse"
        ],
        "thermal_status_after": args.thermal_status_after,
        "thermal_status_after_level": thermal_status_after["level"],
        "thermal_status_after_label": thermal_status_after["label"],
        "thermal_status_after_severe_or_worse": thermal_status_after[
            "severe_or_worse"
        ],
        "thermal_live_corridor_count": 0,
        "thermal_depth_elapsed_ms": 0.0,
        "thermal_depth_fps": 0.0,
        "thermal_tail_depth_elapsed_ms": 0.0,
        "thermal_tail_depth_fps": 0.0,
        "thermal_frame_stats_count": 0,
        "thermal_gap_count": 0,
        "corridor_test_required": parse_bool(args.require_corridor_test),
        "corridor_test_result": args.corridor_test_result,
        "corridor_test_notes": args.corridor_test_notes,
        "log_path": str(args.log),
    }

    if thermal_log:
        details.update(
            {
                "thermal_live_corridor_count": thermal_log["live_corridor_count"],
                "thermal_depth_elapsed_ms": thermal_log["depth_elapsed_ms"],
                "thermal_depth_fps": thermal_log["depth_fps"],
                "thermal_tail_depth_elapsed_ms": thermal_log["tail_depth_elapsed_ms"],
                "thermal_tail_depth_fps": thermal_log["tail_depth_fps"],
                "thermal_frame_stats_count": thermal_log["frame_stats_count"],
                "thermal_gap_count": thermal_log["gap_count"],
            }
        )

    missing: list[str] = []
    add_main_missing(
        missing,
        details,
        require_target_soc=parse_bool(args.require_target_soc),
        require_fp16_htp=parse_bool(args.require_fp16_htp),
        max_depth_ms=max_depth_ms,
        min_depth_fps_label=min_depth_fps_label,
        min_live_corridor_frames=args.min_live_corridor_frames,
        min_frame_stats=args.min_frame_stats,
        require_corridor_feedback=parse_bool(args.require_corridor_feedback),
        require_safe_stop_proof=parse_bool(args.require_safe_stop_proof),
    )

    thermal_missing: list[str] = []
    if thermal_log and args.thermal_minutes_required > 0:
        add_thermal_missing(thermal_missing, details, max_depth_ms, min_depth_fps_label)

    print(json.dumps({"details": details, "missing": missing, "thermal_missing": thermal_missing}, indent=2))


if __name__ == "__main__":
    main()
