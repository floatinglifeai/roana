#!/usr/bin/env python3
"""Analyze Roana iOS log evidence for S0/V0a/V0b code gates."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from statistics import mean


GUIDANCE_COMMANDS = frozenset({"LEFT", "STRAIGHT", "RIGHT"})
EXPECTED_YOLO_RESOURCE = "YOLO11n"
EXPECTED_DEPTH_RESOURCE = "DepthAnythingV2Small"
THERMAL_SEVERITY = {
    "nominal": 0,
    "fair": 1,
    "serious": 2,
    "critical": 3,
    "unknown": 4,
}


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
    yolo_descriptions = []
    depth_ok = []
    depth_descriptions = []
    yolo_description_resources = set()
    depth_description_resources = set()
    yolo_description_inputs = set()
    yolo_description_outputs = set()
    depth_description_inputs = set()
    depth_description_outputs = set()
    corridor_ok = []
    corridor_feedback_spoken = []
    speech_queued = []
    speech_labels = set()
    yolo_detection_labels = set()
    audio_session_active = []
    audio_session_failed = []
    safety_fail_safe_stop = []
    safety_fail_safe_stop_reasons = set()
    yolo_vision_orientation_lines = []
    depth_vision_orientation_lines = []
    lifecycle_lines = []
    lifecycle_events = []
    preview_orientation_lines = []
    capture_orientation_lines = []
    preview_vision_orientations = set()
    capture_vision_orientations = set()
    yolo_vision_orientations = set()
    depth_vision_orientations = set()
    inference_scheduled = []
    inference_skipped = []
    inference_finished = []
    max_backlog = 0
    max_dropped = 0
    max_inference_skipped = 0
    p95_values = []
    run_seconds_values = []
    thermal_states = []

    for line in lines:
        fields = line_fields(line)
        if "roana_ios_frame_stats" in line:
            frame_stats.append(line)
            max_backlog = max(max_backlog, int(numeric_field(fields, "backlog") or 0))
            max_dropped = max(max_dropped, int(numeric_field(fields, "dropped") or 0))
            p95 = numeric_field(fields, "p95_ms")
            if p95 is not None:
                p95_values.append(p95)
            run_seconds = numeric_field(fields, "run_s")
            if run_seconds is not None:
                run_seconds_values.append(run_seconds)
            thermal_state = fields.get("thermal")
            if thermal_state:
                thermal_states.append(thermal_state)
        if "roana_ios_yolo status=model_description" in line:
            yolo_descriptions.append(line)
            resource = fields.get("resource")
            inputs = fields.get("inputs")
            outputs = fields.get("outputs")
            if resource:
                yolo_description_resources.add(resource)
            if inputs:
                yolo_description_inputs.add(inputs)
            if outputs:
                yolo_description_outputs.add(outputs)
        if (
            ("roana_ios_yolo status=ready" in line or "roana_ios_yolo status=ok" in line)
            and "vision=" in line
        ):
            yolo_vision_orientation_lines.append(line)
            vision_orientation = fields.get("vision")
            if vision_orientation:
                yolo_vision_orientations.add(vision_orientation)
            label = fields.get("label")
            if label:
                yolo_detection_labels.add(label)
        if "roana_ios_depth status=model_description" in line:
            depth_descriptions.append(line)
            resource = fields.get("resource")
            inputs = fields.get("inputs")
            outputs = fields.get("outputs")
            if resource:
                depth_description_resources.add(resource)
            if inputs:
                depth_description_inputs.add(inputs)
            if outputs:
                depth_description_outputs.add(outputs)
        if "roana_ios_depth status=ok" in line:
            depth_ok.append(line)
            if "vision=" in line:
                depth_vision_orientation_lines.append(line)
                vision_orientation = fields.get("vision")
                if vision_orientation:
                    depth_vision_orientations.add(vision_orientation)
        if "roana_ios_corridor decision=" in line:
            corridor_ok.append(line)
        if "roana_ios_corridor_feedback status=spoken" in line:
            corridor_feedback_spoken.append(line)
        if "roana_ios_speech status=queued" in line:
            speech_queued.append(line)
            label = fields.get("label")
            if label:
                speech_labels.add(label)
        if "roana_ios_audio_session status=active" in line:
            audio_session_active.append(line)
        if "roana_ios_audio_session status=failed" in line:
            audio_session_failed.append(line)
        if "roana_ios_safety event=fail_safe_stop" in line:
            safety_fail_safe_stop.append(line)
            reason = fields.get("reason")
            if reason:
                safety_fail_safe_stop_reasons.add(reason)
        if "roana_ios_lifecycle" in line:
            lifecycle_lines.append(line)
            if "camera_started" in line:
                lifecycle_events.append("camera_started")
            elif "camera_background_stop" in line:
                lifecycle_events.append("camera_background_stop")
            elif "camera_stopped" in line:
                lifecycle_events.append("camera_stopped")
        if "roana_ios_orientation source=preview" in line:
            preview_orientation_lines.append(line)
            vision_orientation = fields.get("vision")
            if vision_orientation:
                preview_vision_orientations.add(vision_orientation)
        if "roana_ios_lifecycle camera_output_orientation" in line:
            capture_orientation_lines.append(line)
            vision_orientation = fields.get("vision")
            if vision_orientation:
                capture_vision_orientations.add(vision_orientation)
        if "roana_ios_inference status=scheduled" in line:
            inference_scheduled.append(line)
        if "roana_ios_inference status=skipped" in line:
            inference_skipped.append(line)
            max_inference_skipped = max(
                max_inference_skipped,
                int(numeric_field(fields, "skipped") or 0),
            )
        if "roana_ios_inference status=finished" in line:
            inference_finished.append(line)
            max_inference_skipped = max(
                max_inference_skipped,
                int(numeric_field(fields, "skipped") or 0),
            )

    normal_corridor_feedback = ""
    stop_corridor_feedback = ""
    for line in corridor_feedback_spoken:
        fields = line_fields(line)
        command = fields.get("command", "")
        if command in GUIDANCE_COMMANDS and not normal_corridor_feedback:
            normal_corridor_feedback = line
        if command == "STOP" and fields.get("message") == "stop" and not stop_corridor_feedback:
            stop_corridor_feedback = line

    matched_speech_labels = sorted(yolo_detection_labels & speech_labels)

    permission_seen = any("camera_authorization state=" in line for line in lifecycle_lines)
    permission_denied_seen = any(
        "camera_authorization state=denied" in line or "camera_authorization state=restricted" in line
        for line in lifecycle_lines
    )
    camera_permission_denied = any("camera_permission_denied" in line for line in lifecycle_lines)
    camera_started = any("camera_started" in line for line in lifecycle_lines)
    camera_background_stop = any("camera_background_stop" in line for line in lifecycle_lines)
    camera_stopped = any("camera_stopped" in line for line in lifecycle_lines)
    idle_timer_disabled = any("idle_timer_disabled value=true" in line for line in lifecycle_lines)
    idle_timer_enabled = any("idle_timer_disabled value=false" in line for line in lifecycle_lines)
    background_cycle_seen = any(
        event in {"camera_background_stop", "camera_stopped"}
        and "camera_started" in lifecycle_events[index + 1 :]
        for index, event in enumerate(lifecycle_events)
    )

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

    max_thermal_state = "none"
    max_thermal_severity = -1
    for state in thermal_states:
        severity = THERMAL_SEVERITY.get(state, THERMAL_SEVERITY["unknown"])
        if severity > max_thermal_severity:
            max_thermal_state = state
            max_thermal_severity = severity

    return {
        "line_count": len(lines),
        "frame_stats_count": len(frame_stats),
        "max_backlog": max_backlog,
        "max_dropped": max_dropped,
        "max_p95_ms": rounded(max(p95_values), 2) if p95_values else 0.0,
        "max_run_seconds": rounded(max(run_seconds_values), 2) if run_seconds_values else 0.0,
        "max_thermal_state": max_thermal_state,
        "avg_yolo_ms": rounded(mean(yolo_elapsed), 2) if yolo_elapsed else 0.0,
        "avg_depth_ms": rounded(mean(depth_elapsed), 2) if depth_elapsed else 0.0,
        "yolo_description_count": len(yolo_descriptions),
        "depth_description_count": len(depth_descriptions),
        "yolo_description_resources": sorted(yolo_description_resources),
        "depth_description_resources": sorted(depth_description_resources),
        "yolo_description_inputs": sorted(yolo_description_inputs),
        "yolo_description_outputs": sorted(yolo_description_outputs),
        "depth_description_inputs": sorted(depth_description_inputs),
        "depth_description_outputs": sorted(depth_description_outputs),
        "yolo_vision_orientation_count": len(yolo_vision_orientation_lines),
        "depth_vision_orientation_count": len(depth_vision_orientation_lines),
        "preview_vision_orientations": sorted(preview_vision_orientations),
        "capture_vision_orientations": sorted(capture_vision_orientations),
        "yolo_vision_orientations": sorted(yolo_vision_orientations),
        "depth_vision_orientations": sorted(depth_vision_orientations),
        "yolo_ok_count": len(yolo_elapsed),
        "depth_ok_count": len(depth_ok),
        "corridor_count": len(corridor_ok),
        "speech_queued_count": len(speech_queued),
        "speech_labels": sorted(speech_labels),
        "yolo_detection_labels": sorted(yolo_detection_labels),
        "matched_yolo_speech_labels": matched_speech_labels,
        "audio_session_active_count": len(audio_session_active),
        "audio_session_failed_count": len(audio_session_failed),
        "safety_fail_safe_stop_count": len(safety_fail_safe_stop),
        "safety_fail_safe_stop_reasons": sorted(safety_fail_safe_stop_reasons),
        "preview_orientation_count": len(preview_orientation_lines),
        "capture_orientation_count": len(capture_orientation_lines),
        "inference_scheduled_count": len(inference_scheduled),
        "inference_skipped_count": len(inference_skipped),
        "inference_finished_count": len(inference_finished),
        "max_inference_skipped": max_inference_skipped,
        "corridor_feedback_spoken_count": len(corridor_feedback_spoken),
        "normal_corridor_feedback": normal_corridor_feedback,
        "stop_corridor_feedback": stop_corridor_feedback,
        "permission_seen": permission_seen,
        "permission_denied_seen": permission_denied_seen,
        "camera_permission_denied": camera_permission_denied,
        "camera_started": camera_started,
        "camera_background_stop": camera_background_stop,
        "camera_stopped": camera_stopped,
        "idle_timer_disabled": idle_timer_disabled,
        "idle_timer_enabled": idle_timer_enabled,
        "background_cycle_seen": background_cycle_seen,
    }


def missing_evidence(
    details: dict[str, object],
    *,
    min_frame_stats: int,
    min_run_seconds: float,
    max_backlog: int,
    max_dropped: int,
    max_p95_ms: float,
    max_thermal_state: str,
    require_yolo: bool,
    require_yolo_description: bool,
    require_depth: bool,
    require_depth_description: bool,
    require_vision_orientation: bool,
    require_corridor: bool,
    require_speech: bool,
    require_orientation: bool,
    require_background_stop: bool,
    require_background_cycle: bool,
    require_idle_timer: bool,
    require_permission: bool,
    require_permission_denied: bool,
    require_camera_start: bool,
    require_inference: bool,
    require_fail_safe_stop: bool,
    max_inference_skipped: int,
) -> list[str]:
    missing: list[str] = []
    if details["frame_stats_count"] < min_frame_stats:
        missing.append(f"frame_stats>={min_frame_stats}")
    if details["max_run_seconds"] < min_run_seconds:
        missing.append(f"run_s>={min_run_seconds:g}")
    if details["max_backlog"] > max_backlog:
        missing.append(f"backlog<={max_backlog}")
    if details["max_dropped"] > max_dropped:
        missing.append(f"dropped<={max_dropped}")
    if max_p95_ms > 0 and details["max_p95_ms"] > max_p95_ms:
        missing.append(f"p95_ms<={max_p95_ms:g}")
    if max_thermal_state != "none":
        allowed_severity = THERMAL_SEVERITY.get(max_thermal_state, THERMAL_SEVERITY["unknown"])
        observed_state = str(details["max_thermal_state"])
        observed_severity = THERMAL_SEVERITY.get(observed_state, THERMAL_SEVERITY["unknown"])
        if observed_severity > allowed_severity:
            missing.append(f"thermal<={max_thermal_state}")
    if require_permission and not details["permission_seen"]:
        missing.append("camera_permission_state")
    if require_permission_denied and not details["permission_denied_seen"]:
        missing.append("camera_permission_denied_state")
    if require_permission_denied and not details["camera_permission_denied"]:
        missing.append("camera_permission_denied_ui")
    if require_camera_start and not details["camera_started"]:
        missing.append("camera_started")
    if require_background_stop and not (
        details["camera_background_stop"] or details["camera_stopped"]
    ):
        missing.append("camera_background_stop")
    if require_background_cycle and not details["background_cycle_seen"]:
        missing.append("camera_background_restart")
    if require_idle_timer and not details["idle_timer_disabled"]:
        missing.append("idle_timer_disabled")
    if require_idle_timer and not details["idle_timer_enabled"]:
        missing.append("idle_timer_enabled")
    if require_yolo and details["yolo_ok_count"] < 1:
        missing.append("yolo_inference")
    if require_yolo_description and details["yolo_description_count"] < 1:
        missing.append("yolo_model_description")
    if require_yolo_description and details["yolo_description_count"] >= 1:
        if EXPECTED_YOLO_RESOURCE not in details["yolo_description_resources"]:
            missing.append("yolo_model_resource")
        if not has_model_feature_contract(
            inputs=details["yolo_description_inputs"],
            outputs=details["yolo_description_outputs"],
            required_input="image_",
            required_output=None,
        ):
            missing.append("yolo_model_features")
    if require_depth and details["depth_ok_count"] < 1:
        missing.append("depth_inference")
    if require_depth_description and details["depth_description_count"] < 1:
        missing.append("depth_model_description")
    if require_depth_description and details["depth_description_count"] >= 1:
        if EXPECTED_DEPTH_RESOURCE not in details["depth_description_resources"]:
            missing.append("depth_model_resource")
        if not has_model_feature_contract(
            inputs=details["depth_description_inputs"],
            outputs=details["depth_description_outputs"],
            required_input="image_",
            required_output="multiarray_",
        ):
            missing.append("depth_model_features")
    if require_vision_orientation and require_yolo and details["yolo_vision_orientation_count"] < 1:
        missing.append("yolo_vision_orientation")
    if require_vision_orientation and require_depth and details["depth_vision_orientation_count"] < 1:
        missing.append("depth_vision_orientation")
    if require_vision_orientation:
        camera_vision = set(details["preview_vision_orientations"]) | set(details["capture_vision_orientations"])
        if require_orientation and not camera_vision:
            missing.append("camera_vision_orientation")
        if require_yolo and details["yolo_vision_orientation_count"] >= 1:
            yolo_vision = set(details["yolo_vision_orientations"])
            if camera_vision and not yolo_vision.issubset(camera_vision):
                missing.append("yolo_vision_orientation_match")
        if require_depth and details["depth_vision_orientation_count"] >= 1:
            depth_vision = set(details["depth_vision_orientations"])
            if camera_vision and not depth_vision.issubset(camera_vision):
                missing.append("depth_vision_orientation_match")
    if require_corridor and details["corridor_count"] < 1:
        missing.append("corridor_decision")
    if require_speech and details["speech_queued_count"] < 1:
        missing.append("speech_queued")
    if require_speech and require_yolo and not details["matched_yolo_speech_labels"]:
        missing.append("yolo_speech_match")
    if (require_speech or require_corridor) and details["audio_session_active_count"] < 1:
        missing.append("audio_session_active")
    if (require_speech or require_corridor) and details["audio_session_failed_count"] > 0:
        missing.append("audio_session_no_failure")
    if require_orientation and details["preview_orientation_count"] < 1:
        missing.append("preview_orientation")
    if require_orientation and details["capture_orientation_count"] < 1:
        missing.append("capture_orientation")
    if require_inference and details["inference_finished_count"] < 1:
        missing.append("inference_finished")
    if require_fail_safe_stop and details["safety_fail_safe_stop_count"] < 1:
        missing.append("fail_safe_stop")
    if details["max_inference_skipped"] > max_inference_skipped:
        missing.append(f"inference_skipped<={max_inference_skipped}")
    if require_corridor and not details["normal_corridor_feedback"]:
        missing.append("corridor_guidance_feedback")
    if require_corridor and not details["stop_corridor_feedback"]:
        missing.append("corridor_stop_feedback")
    return missing


def has_model_feature_contract(
    *,
    inputs: object,
    outputs: object,
    required_input: str | None,
    required_output: str | None,
) -> bool:
    input_values = [str(value) for value in inputs if str(value) not in {"", "unknown"}]
    output_values = [str(value) for value in outputs if str(value) not in {"", "unknown"}]
    if not input_values or not output_values:
        return False
    if required_input and not any(required_input in value for value in input_values):
        return False
    if required_output and not any(required_output in value for value in output_values):
        return False
    return True


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--min-frame-stats", default=120, type=int)
    parser.add_argument("--min-run-seconds", default=0.0, type=float)
    parser.add_argument("--max-backlog", default=0, type=int)
    parser.add_argument("--max-dropped", default=0, type=int)
    parser.add_argument("--max-p95-ms", default=0.0, type=float)
    parser.add_argument(
        "--max-thermal-state",
        choices=("none", "nominal", "fair", "serious", "critical"),
        default="none",
    )
    parser.add_argument("--max-inference-skipped", default=0, type=int)
    parser.add_argument("--require-yolo", default="0")
    parser.add_argument("--require-yolo-description", default="0")
    parser.add_argument("--require-depth", default="0")
    parser.add_argument("--require-depth-description", default="0")
    parser.add_argument("--require-vision-orientation", default="0")
    parser.add_argument("--require-corridor", default="0")
    parser.add_argument("--require-speech", default="0")
    parser.add_argument("--require-orientation", default="0")
    parser.add_argument("--require-inference", default="0")
    parser.add_argument("--require-fail-safe-stop", default="0")
    parser.add_argument("--require-background-stop", default="0")
    parser.add_argument("--require-background-cycle", default="0")
    parser.add_argument("--require-idle-timer", default="0")
    parser.add_argument("--require-permission", default="1")
    parser.add_argument("--require-permission-denied", default="0")
    parser.add_argument("--require-camera-start", default="1")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    details = parse_log(args.log)
    missing = missing_evidence(
        details,
        min_frame_stats=args.min_frame_stats,
        min_run_seconds=args.min_run_seconds,
        max_backlog=args.max_backlog,
        max_dropped=args.max_dropped,
        max_p95_ms=args.max_p95_ms,
        max_thermal_state=args.max_thermal_state,
        require_yolo=parse_bool(args.require_yolo),
        require_yolo_description=parse_bool(args.require_yolo_description),
        require_depth=parse_bool(args.require_depth),
        require_depth_description=parse_bool(args.require_depth_description),
        require_vision_orientation=parse_bool(args.require_vision_orientation),
        require_corridor=parse_bool(args.require_corridor),
        require_speech=parse_bool(args.require_speech),
        require_orientation=parse_bool(args.require_orientation),
        require_background_stop=parse_bool(args.require_background_stop),
        require_background_cycle=parse_bool(args.require_background_cycle),
        require_idle_timer=parse_bool(args.require_idle_timer),
        require_permission=parse_bool(args.require_permission),
        require_permission_denied=parse_bool(args.require_permission_denied),
        require_camera_start=parse_bool(args.require_camera_start),
        require_inference=parse_bool(args.require_inference),
        require_fail_safe_stop=parse_bool(args.require_fail_safe_stop),
        max_inference_skipped=args.max_inference_skipped,
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
