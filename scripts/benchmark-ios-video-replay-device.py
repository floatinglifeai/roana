#!/usr/bin/env python3
"""Run fixed-video iOS replay benchmark on a physical iPhone."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT = REPO_ROOT / "ios/Roana/Roana.xcodeproj"
ASSET_CHECKER = REPO_ROOT / "scripts/check-ios-model-assets.py"
VERIFY_REPLAY = REPO_ROOT / "scripts/verify-ios-replay-log.py"
DEVICE_VERIFIER = REPO_ROOT / "scripts/verify-ios-device-log.py"
DEVICE_VERIFIER_SPEC = importlib.util.spec_from_file_location("verify_ios_device_log", DEVICE_VERIFIER)
assert DEVICE_VERIFIER_SPEC is not None
verify_ios_device_log = importlib.util.module_from_spec(DEVICE_VERIFIER_SPEC)
assert DEVICE_VERIFIER_SPEC.loader is not None
DEVICE_VERIFIER_SPEC.loader.exec_module(verify_ios_device_log)


DEFAULT_DEVICE = "A85B7E8D-1EDD-573F-9C50-BC76B9FB8E03"
DEFAULT_DERIVED_DATA = Path("/tmp/roana-ios-video-replay-derived-data")
APP_ID = "app.roana.ios"
PROFILE_DIRS = [
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
]


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def safe_stem(path: Path) -> str:
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", path.stem).strip("-")
    return stem or "video"


def run(command: list[str], *, timeout: float | None = None) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return completed.returncode, completed.stdout + completed.stderr
    except subprocess.TimeoutExpired as error:
        output = timeout_text(error.stdout) + timeout_text(error.stderr)
        return 124, output


def timeout_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def json_result(
    *,
    status: str,
    artifact: Path | None,
    result: Path,
    decision: str,
    details: dict[str, Any] | None = None,
    missing: list[str] | None = None,
) -> int:
    payload = {
        "status": status,
        "hypothesis": (
            "iOS replays a fixed local video through the Core ML YOLO + "
            "Depth corridor stack for comparable Android/iOS benchmarks"
        ),
        "artifact": "" if artifact is None else str(artifact),
        "result": str(result),
        "decision": decision,
        "missing": sorted(set(missing or [])),
        "details": details or {},
    }
    write_json(result, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if status == "passed" else 2 if status == "blocked" else 1


def artifact_paths(video: Path, *, output_dir: Path, requested_timestamp: str) -> dict[str, Path]:
    prefix = f"ios-video-replay-{safe_stem(video)}-{requested_timestamp}"
    return {
        "log": output_dir / f"{prefix}.log",
        "result": output_dir / f"{prefix}.json",
        "verify": output_dir / f"{prefix}.verify.json",
    }


def app_path(*, derived_data_path: Path) -> Path:
    return derived_data_path / "Build/Products/Debug-iphoneos/Roana.app"


def infer_team_id_from_keychain() -> str:
    status, output = run(["security", "find-identity", "-v", "-p", "codesigning"])
    if status != 0:
        return ""
    team_ids = []
    for line in output.splitlines():
        match = re.search(r'"Apple Development: .* \(([A-Z0-9]{10})\)"', line)
        if match:
            team_ids.append(match.group(1))
    return team_ids[0] if len(team_ids) == 1 else ""


def decode_mobileprovision(path: Path) -> dict[str, Any] | None:
    status, output = run(["security", "cms", "-D", "-i", str(path)])
    if status != 0:
        return None
    try:
        decoded = plistlib.loads(output.encode("utf-8"))
    except plistlib.InvalidFileException:
        return None
    return decoded if isinstance(decoded, dict) else None


def infer_team_id_from_profiles(
    *,
    app_id: str = APP_ID,
    device_udid: str = "00008150-000E35310E82401C",
) -> str:
    for profile_dir in PROFILE_DIRS:
        if not profile_dir.is_dir():
            continue
        for profile in sorted(profile_dir.glob("*.mobileprovision")):
            decoded = decode_mobileprovision(profile)
            if decoded is None:
                continue
            entitlements = decoded.get("Entitlements", {})
            application_id = entitlements.get("application-identifier", "") if isinstance(entitlements, dict) else ""
            if not str(application_id).endswith(f".{app_id}"):
                continue
            devices = decoded.get("ProvisionedDevices", [])
            if device_udid and isinstance(devices, list) and device_udid not in devices:
                continue
            teams = decoded.get("TeamIdentifier", [])
            if isinstance(teams, list) and len(teams) == 1:
                return str(teams[0])
    return ""


def resolve_team_id() -> tuple[str, str]:
    team_id = os.environ.get("ROANA_IOS_DEVELOPMENT_TEAM", "").strip()
    if team_id:
        return team_id, "environment"
    profile_team = infer_team_id_from_profiles()
    if profile_team:
        return profile_team, "provisioning_profile"
    inferred = infer_team_id_from_keychain()
    if inferred:
        return inferred, "keychain"
    return "", "missing"


def build_command(*, team_id: str, device: str, derived_data_path: Path) -> list[str]:
    return [
        "xcodebuild",
        "-project",
        str(PROJECT),
        "-scheme",
        "Roana-V0b-Corridor",
        "-destination",
        f"id={device}",
        "-derivedDataPath",
        str(derived_data_path),
        f"DEVELOPMENT_TEAM={team_id}",
        "-allowProvisioningUpdates",
        "build",
    ]


def install_command(*, device: str, app: Path) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "device",
        "install",
        "app",
        "--device",
        device,
        str(app),
    ]


def copy_video_command(*, device: str, source_dir: Path) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "device",
        "copy",
        "to",
        "--device",
        device,
        "--source",
        str(source_dir),
        "--destination",
        "Documents",
        "--domain-type",
        "appDataContainer",
        "--domain-identifier",
        APP_ID,
    ]


def materialize_app_model_asset_symlinks(app: Path) -> list[str]:
    materialized: list[str] = []
    assets = app / "ModelAssets"
    if not assets.is_dir():
        return materialized
    for path in sorted(assets.iterdir()):
        if not path.is_symlink():
            continue
        target = path.resolve(strict=True)
        temporary_path = path.with_name(f".{path.name}.materialized")
        if temporary_path.exists() or temporary_path.is_symlink():
            if temporary_path.is_dir() and not temporary_path.is_symlink():
                shutil.rmtree(temporary_path)
            else:
                temporary_path.unlink()
        shutil.copytree(target, temporary_path, symlinks=False)
        path.unlink()
        temporary_path.rename(path)
        materialized.append(path.name)
    return materialized


def signing_identity_for_app(app: Path) -> str:
    status, output = run(["codesign", "-dvv", str(app)])
    if status != 0:
        return ""
    for line in output.splitlines():
        if line.startswith("Authority=Apple Development:"):
            return line.removeprefix("Authority=").strip()
    return ""


def app_entitlements_path(*, derived_data_path: Path) -> Path:
    return (
        derived_data_path /
        "Build/Intermediates.noindex/Roana.build/Debug-iphoneos/Roana.build/Roana.app.xcent"
    )


def resign_app(app: Path, *, derived_data_path: Path) -> tuple[int, str]:
    identity = signing_identity_for_app(app)
    if not identity:
        return 1, "Could not infer app signing identity."
    entitlements = app_entitlements_path(derived_data_path=derived_data_path)
    if not entitlements.is_file():
        return 1, f"Missing entitlements file: {entitlements}"
    return run(
        [
            "codesign",
            "--force",
            "--sign",
            identity,
            "--entitlements",
            str(entitlements),
            str(app),
        ],
    )


def launch_command(*, device: str, video_name: str, fps: float, max_seconds: float | None) -> list[str]:
    command = [
        "xcrun",
        "devicectl",
        "device",
        "process",
        "launch",
        "--device",
        device,
        "--terminate-existing",
        "--console",
        APP_ID,
        "--roana-enable-corridor",
        "--roana-replay-video",
        video_name,
        "--roana-replay-fps",
        f"{fps:g}",
    ]
    if max_seconds is not None:
        command.extend(["--roana-replay-max-seconds", f"{max_seconds:g}"])
    return command


def verify_replay_command(
    *,
    log: Path,
    min_run_seconds: float,
    max_p95_ms: float,
) -> list[str]:
    return [
        str(VERIFY_REPLAY),
        "--log",
        str(log),
        "--fixture",
        "stop",
        "--min-run-seconds",
        f"{min_run_seconds:g}",
        "--max-p95-ms",
        f"{max_p95_ms:g}",
        "--require-audio-session",
        "0",
        "--require-corridor-guidance",
        "0",
    ]


def physical_commands(
    *,
    team_id: str,
    device: str,
    derived_data_path: Path,
    source_dir: Path,
    video_name: str,
    fps: float,
    max_seconds: float | None,
) -> list[list[str]]:
    return [
        build_command(team_id=team_id, device=device, derived_data_path=derived_data_path),
        install_command(device=device, app=app_path(derived_data_path=derived_data_path)),
        copy_video_command(device=device, source_dir=source_dir),
        launch_command(device=device, video_name=video_name, fps=fps, max_seconds=max_seconds),
    ]


def parse_json_output(output: str) -> dict[str, Any]:
    try:
        parsed = json.loads(output)
    except json.JSONDecodeError:
        return {"status": "failed", "missing": ["json_output"], "raw": output}
    return parsed if isinstance(parsed, dict) else {"status": "failed", "missing": ["json_object"], "raw": parsed}


def classify_setup_failure(output: str) -> tuple[str, list[str]]:
    missing: list[str] = ["command_failed"]
    if "No Account for Team" in output:
        missing.append("xcode_account")
    if "No profiles for" in output or "provisioning profiles matching" in output:
        missing.append("provisioning_profile")
    if "device was not, or could not be, unlocked" in output:
        missing.append("iphone_unlocked")
    if "Invalid symlink" in output and "ModelAssets" in output:
        missing.append("model_asset_symlink")
    status = "blocked" if len(missing) > 1 else "failed"
    return status, sorted(set(missing))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=DEFAULT_DEVICE)
    parser.add_argument("--video", type=Path, default=REPO_ROOT / "samples/iphone_0530.mp4")
    parser.add_argument("--fps", type=float, default=10.0)
    parser.add_argument("--max-seconds", type=float)
    parser.add_argument("--output-dir", type=Path, default=REPO_ROOT / "logs")
    parser.add_argument("--timestamp", default=timestamp())
    parser.add_argument("--derived-data-path", type=Path, default=DEFAULT_DERIVED_DATA)
    parser.add_argument("--launch-timeout-seconds", type=float, default=360.0)
    parser.add_argument("--min-run-seconds", type=float, default=80.0)
    parser.add_argument("--max-p95-ms", type=float, default=120.0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-host-checks", action="store_true")
    return parser


def prerequisites(args: argparse.Namespace, *, team_id: str) -> list[str]:
    missing: list[str] = []
    if not team_id:
        missing.append("ROANA_IOS_DEVELOPMENT_TEAM")
    if not args.video.is_file():
        missing.append("video_file")

    asset_status, _ = run([str(ASSET_CHECKER), "--require-present"])
    if asset_status != 0:
        missing.append("model_assets")

    missing.extend(
        verify_ios_device_log.host_readiness(
            require_device=True,
            skip_host_checks=args.skip_host_checks,
            target_identifier=args.device,
        ),
    )
    return sorted(set(missing))


def main() -> int:
    args = build_parser().parse_args()
    paths = artifact_paths(args.video, output_dir=args.output_dir, requested_timestamp=args.timestamp)
    team_id, team_source = resolve_team_id()
    missing = prerequisites(args, team_id=team_id)

    with tempfile.TemporaryDirectory() as temp_dir:
        source_root = Path(temp_dir) / "ios-replay-source"
        replay_dir = source_root / "replay"
        replay_dir.mkdir(parents=True)
        video_name = args.video.name
        if args.video.is_file():
            shutil.copy2(args.video, replay_dir / video_name)

        if args.dry_run or missing:
            details: dict[str, Any] = {
                "teamSource": team_source,
                "video": str(args.video),
            }
            if team_id:
                details["commands"] = physical_commands(
                    team_id=team_id,
                    device=args.device,
                    derived_data_path=args.derived_data_path,
                    source_dir=replay_dir,
                    video_name=video_name,
                    fps=args.fps,
                    max_seconds=args.max_seconds,
                )
            if missing:
                return json_result(
                    status="blocked",
                    artifact=None,
                    result=paths["result"],
                    decision="iOS video replay prerequisites are not ready.",
                    details=details,
                    missing=missing,
                )
            return json_result(
                status="passed",
                artifact=None,
                result=paths["result"],
                decision="Dry run only; commands were not executed.",
                details=details,
            )

        args.output_dir.mkdir(parents=True, exist_ok=True)
        commands = physical_commands(
            team_id=team_id,
            device=args.device,
            derived_data_path=args.derived_data_path,
            source_dir=replay_dir,
            video_name=video_name,
            fps=args.fps,
            max_seconds=args.max_seconds,
        )

        materialized_assets: list[str] = []
        for command in commands[:3]:
            status, output = run(command)
            if status != 0:
                failure_status, failure_missing = classify_setup_failure(output)
                return json_result(
                    status=failure_status,
                    artifact=paths["log"] if paths["log"].is_file() else None,
                    result=paths["result"],
                    decision="iOS video replay setup command failed.",
                    details={"command": command, "output": output, "teamSource": team_source},
                    missing=failure_missing,
                )
            if command == commands[0]:
                materialized_assets = materialize_app_model_asset_symlinks(
                    app_path(derived_data_path=args.derived_data_path),
                )
                if materialized_assets:
                    resign_status, resign_output = resign_app(
                        app_path(derived_data_path=args.derived_data_path),
                        derived_data_path=args.derived_data_path,
                    )
                    if resign_status != 0:
                        return json_result(
                            status="failed",
                            artifact=None,
                            result=paths["result"],
                            decision="iOS video replay app re-sign failed after materializing model assets.",
                            details={
                                "output": resign_output,
                                "materializedModelAssets": materialized_assets,
                                "teamSource": team_source,
                            },
                            missing=["codesign_failed"],
                        )

        launch_status, launch_output = run(commands[3], timeout=args.launch_timeout_seconds)
        paths["log"].write_text(launch_output, encoding="utf-8")
        if launch_status != 0:
            failure_status, failure_missing = classify_setup_failure(launch_output)
            return json_result(
                status=failure_status,
                artifact=paths["log"],
                result=paths["result"],
                decision="iOS video replay launch failed or timed out.",
                details={
                    "command": commands[3],
                    "exitStatus": launch_status,
                    "tail": "\n".join(launch_output.splitlines()[-120:]),
                    "materializedModelAssets": materialized_assets,
                    "teamSource": team_source,
                },
                missing=["launch_failed", *failure_missing],
            )

        verify_status, verify_output = run(
            verify_replay_command(
                log=paths["log"],
                min_run_seconds=args.min_run_seconds,
                max_p95_ms=args.max_p95_ms,
            ),
        )
        verify_json = parse_json_output(verify_output)
        write_json(paths["verify"], verify_json)

        if verify_status != 0:
            return json_result(
                status="blocked",
                artifact=paths["log"],
                result=paths["result"],
                decision="iOS video replay ran, but verification did not pass.",
                details={
                    "verify": verify_json,
                    "verifyArtifact": str(paths["verify"]),
                    "materializedModelAssets": materialized_assets,
                    "teamSource": team_source,
                },
                missing=["replay_verification", *[str(item) for item in verify_json.get("missing", [])]],
            )

        return json_result(
            status="passed",
            artifact=paths["log"],
            result=paths["result"],
            decision="iOS video replay benchmark completed on the fixed sample video.",
            details={
                "verify": verify_json,
                "verifyArtifact": str(paths["verify"]),
                "materializedModelAssets": materialized_assets,
                "teamSource": team_source,
            },
        )


if __name__ == "__main__":
    raise SystemExit(main())
