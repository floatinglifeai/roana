#!/usr/bin/env python3
"""Validate iOS physical-device log artifacts for S0/V0a/V0b gates."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ANALYZER = REPO_ROOT / "scripts/analyze-ios-log.py"
ASSET_CHECKER = REPO_ROOT / "scripts/check-ios-model-assets.py"
XCODEBUILD_MISSING = "xcodebuild"
DEVICEXCRUN_MISSING = "xcrun devicectl"


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "y"}


def run_command(command: list[str]) -> tuple[int, str]:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    return completed.returncode, completed.stdout + completed.stderr


def device_matches_identifier(device: dict[str, object], target_identifier: str | None) -> bool:
    if target_identifier is None:
        return True
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    values = {
        str(device.get("identifier", "")),
        str(hardware.get("udid", "")) if isinstance(hardware, dict) else "",
    }
    if isinstance(connection, dict):
        values.update(str(value) for value in connection.get("potentialHostnames", []))
    return target_identifier in values


def iphone_device_readiness_from_devicectl_json(
    text: str,
    *,
    target_identifier: str | None = None,
) -> list[str]:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return ["iphone_device"]

    devices = payload.get("result", {}).get("devices", [])
    iphone_devices = []
    available_devices = []
    for device in devices:
        hardware = device.get("hardwareProperties", {})
        if hardware.get("platform") != "iOS" or hardware.get("deviceType") != "iPhone":
            continue
        if not device_matches_identifier(device, target_identifier):
            continue

        iphone_devices.append(device)
        connection = device.get("connectionProperties", {})
        properties = device.get("deviceProperties", {})
        tunnel_state = str(connection.get("tunnelState", "")).lower()
        if tunnel_state and tunnel_state != "unavailable":
            available_devices.append(device)
        elif properties.get("ddiServicesAvailable") is True:
            available_devices.append(device)

    if not iphone_devices:
        if target_identifier is not None:
            return ["iphone_device_target"]
        return ["iphone_device"]
    if not available_devices:
        if target_identifier is not None:
            return ["iphone_device_target_available"]
        return ["iphone_device_available"]
    return []


def devicectl_device_readiness(*, target_identifier: str | None = None) -> list[str]:
    with tempfile.TemporaryDirectory() as tmp:
        output_path = Path(tmp) / "devices.json"
        status, _ = run_command(
            [
                "xcrun",
                "devicectl",
                "list",
                "devices",
                "--json-output",
                str(output_path),
            ],
        )
        if status != 0 or not output_path.is_file():
            return [DEVICEXCRUN_MISSING]
        return iphone_device_readiness_from_devicectl_json(
            output_path.read_text(encoding="utf-8"),
            target_identifier=target_identifier,
        )


def host_readiness(
    *,
    require_device: bool,
    skip_host_checks: bool,
    target_identifier: str | None = None,
) -> list[str]:
    missing: list[str] = []
    if skip_host_checks:
        return missing

    xcodebuild = shutil.which("xcodebuild")
    if xcodebuild is None:
        missing.append(XCODEBUILD_MISSING)
    else:
        status, output = run_command([xcodebuild, "-version"])
        if status != 0 or "requires Xcode" in output:
            missing.append("full_xcode")

    xcrun = shutil.which("xcrun")
    if require_device:
        if xcrun is None:
            missing.append(DEVICEXCRUN_MISSING)
        else:
            missing.extend(devicectl_device_readiness(target_identifier=target_identifier))
    return missing


def asset_readiness(*, require_assets: bool) -> list[str]:
    if not require_assets:
        return []
    status, output = run_command([str(ASSET_CHECKER), "--require-present"])
    if status == 0:
        return []
    try:
        details = json.loads(output)
        return [f"model_asset:{model}" for model in details.get("missing", [])]
    except json.JSONDecodeError:
        return ["model_assets"]


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
        "--require-background-stop",
        args.require_background_stop,
        "--require-background-cycle",
        args.require_background_cycle,
        "--require-idle-timer",
        args.require_idle_timer,
        "--require-yolo",
        args.require_yolo,
        "--require-yolo-description",
        args.require_yolo_description,
        "--require-depth",
        args.require_depth,
        "--require-depth-description",
        args.require_depth_description,
        "--require-vision-orientation",
        args.require_vision_orientation,
        "--require-corridor",
        args.require_corridor,
        "--require-speech",
        args.require_speech,
        "--require-orientation",
        args.require_orientation,
        "--require-inference",
        args.require_inference,
        "--require-fail-safe-stop",
        args.require_fail_safe_stop,
        "--require-model-mode",
        args.require_model_mode,
        "--require-permission",
        args.require_permission,
        "--require-permission-denied",
        args.require_permission_denied,
        "--require-camera-start",
        args.require_camera_start,
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
    parser.add_argument("--gate", choices=("s0", "s0-denied", "v0a", "v0b"), default="s0")
    parser.add_argument("--min-frame-stats", default=120, type=int)
    parser.add_argument("--min-run-seconds", default=None, type=float)
    parser.add_argument("--max-backlog", default=0, type=int)
    parser.add_argument("--max-dropped", default=0, type=int)
    parser.add_argument("--max-p95-ms", default=None, type=float)
    parser.add_argument(
        "--max-thermal-state",
        choices=("none", "nominal", "fair", "serious", "critical"),
        default=None,
    )
    parser.add_argument("--max-inference-skipped", default=None, type=int)
    parser.add_argument("--require-background-stop", default="1")
    parser.add_argument("--require-background-cycle", default=None)
    parser.add_argument("--require-idle-timer", default=None)
    parser.add_argument("--require-permission", default="1")
    parser.add_argument("--require-permission-denied", default=None)
    parser.add_argument("--require-camera-start", default=None)
    parser.add_argument("--require-device", default="1")
    parser.add_argument("--skip-host-checks", action="store_true")
    parser.add_argument("--require-model-assets", default=None)
    parser.add_argument("--require-yolo", default=None)
    parser.add_argument("--require-yolo-description", default=None)
    parser.add_argument("--require-depth", default=None)
    parser.add_argument("--require-depth-description", default=None)
    parser.add_argument("--require-vision-orientation", default=None)
    parser.add_argument("--require-corridor", default=None)
    parser.add_argument("--require-speech", default=None)
    parser.add_argument("--require-orientation", default=None)
    parser.add_argument("--require-inference", default=None)
    parser.add_argument("--require-fail-safe-stop", default=None)
    parser.add_argument("--require-model-mode", choices=("none", "disabled", "yolo", "corridor"), default=None)
    return parser


def apply_gate_defaults(args: argparse.Namespace) -> argparse.Namespace:
    denied_gate = args.gate == "s0-denied"
    model_gate = args.gate in {"v0a", "v0b"}
    corridor_gate = args.gate == "v0b"

    if args.require_model_assets is None:
        args.require_model_assets = "1" if model_gate else "0"
    if args.min_run_seconds is None:
        args.min_run_seconds = 0.0 if denied_gate else 60.0
    if args.max_p95_ms is None:
        args.max_p95_ms = 101.0 if corridor_gate else 0.0
    if args.max_inference_skipped is None:
        args.max_inference_skipped = 5 if corridor_gate else 0
    if args.max_thermal_state is None:
        args.max_thermal_state = "fair" if corridor_gate else "none"
    if denied_gate:
        args.min_frame_stats = 0
        args.min_run_seconds = 0.0
        args.max_backlog = max(args.max_backlog, 0)
        args.max_dropped = max(args.max_dropped, 0)
        args.require_background_stop = "0"
        args.require_background_cycle = "0" if args.require_background_cycle is None else args.require_background_cycle
        args.require_idle_timer = "0" if args.require_idle_timer is None else args.require_idle_timer
        args.require_orientation = "0" if args.require_orientation is None else args.require_orientation
    if args.require_yolo is None:
        args.require_yolo = "1" if model_gate else "0"
    if args.require_background_cycle is None:
        args.require_background_cycle = "1"
    if args.require_idle_timer is None:
        args.require_idle_timer = "1"
    if args.require_yolo_description is None:
        args.require_yolo_description = "1" if model_gate else "0"
    if args.require_depth is None:
        args.require_depth = "1" if corridor_gate else "0"
    if args.require_depth_description is None:
        args.require_depth_description = "1" if corridor_gate else "0"
    if args.require_vision_orientation is None:
        args.require_vision_orientation = "1" if model_gate else "0"
    if args.require_corridor is None:
        args.require_corridor = "1" if corridor_gate else "0"
    if args.require_speech is None:
        args.require_speech = "1" if model_gate and not corridor_gate else "0"
    if args.require_orientation is None:
        args.require_orientation = "1"
    if args.require_permission_denied is None:
        args.require_permission_denied = "1" if denied_gate else "0"
    if args.require_camera_start is None:
        args.require_camera_start = "0" if denied_gate else "1"
    if args.require_inference is None:
        args.require_inference = "1" if model_gate else "0"
    if args.require_fail_safe_stop is None:
        args.require_fail_safe_stop = "1" if corridor_gate else "0"
    if args.require_model_mode is None:
        if corridor_gate:
            args.require_model_mode = "corridor"
        elif model_gate:
            args.require_model_mode = "yolo"
        else:
            args.require_model_mode = "disabled"
    return args


def main() -> int:
    args = apply_gate_defaults(build_parser().parse_args())

    missing: list[str] = []
    if not args.log.is_file():
        missing.append("log_file")

    missing.extend(
        host_readiness(
            require_device=parse_bool(args.require_device),
            skip_host_checks=args.skip_host_checks,
        ),
    )
    missing.extend(asset_readiness(require_assets=parse_bool(args.require_model_assets)))

    analysis = None
    if args.log.is_file():
        analysis = analyze_log(args)
        missing.extend(analysis.get("missing", []))

    status = "passed" if not missing else "blocked"
    print(
        json.dumps(
            {
                "status": status,
                "gate": args.gate,
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
