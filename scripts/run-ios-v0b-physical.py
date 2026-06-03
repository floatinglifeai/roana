#!/usr/bin/env python3
"""Build, install, launch, capture, and verify the iOS V0b physical gate."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT = REPO_ROOT / "ios/Roana/Roana.xcodeproj"
DERIVED_DATA_PATH = Path("/tmp/roana-ios-v0b-derived-data")
ASSET_CHECKER = REPO_ROOT / "scripts/check-ios-model-assets.py"
CAPTURE = REPO_ROOT / "scripts/capture-ios-device-log.py"
DEVICE_VERIFIER = REPO_ROOT / "scripts/verify-ios-device-log.py"
DEVICE_VERIFIER_SPEC = importlib.util.spec_from_file_location("verify_ios_device_log", DEVICE_VERIFIER)
assert DEVICE_VERIFIER_SPEC is not None
verify_ios_device_log = importlib.util.module_from_spec(DEVICE_VERIFIER_SPEC)
assert DEVICE_VERIFIER_SPEC.loader is not None
DEVICE_VERIFIER_SPEC.loader.exec_module(verify_ios_device_log)


def run(command: list[str]) -> tuple[int, str]:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    return completed.returncode, completed.stdout + completed.stderr


def json_result(
    *,
    status: str,
    missing: list[str],
    message: str,
    details: dict[str, object] | None = None,
) -> int:
    print(
        json.dumps(
            {
                "status": status,
                "missing": missing,
                "message": message,
                "details": details or {},
            },
            indent=2,
            sort_keys=True,
        ),
    )
    return 0 if status == "passed" else 2 if status == "blocked" else 1


def app_path(*, derived_data_path: Path) -> Path:
    return derived_data_path / "Build/Products/Debug-iphoneos/Roana.app"


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


def install_command(*, device: str, app_path: Path) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "device",
        "install",
        "app",
        "--device",
        device,
        str(app_path),
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


def capture_command(*, device: str, log_dir: Path, capture_seconds: float) -> list[str]:
    return [
        str(CAPTURE),
        "--gate",
        "v0b",
        "--log-dir",
        str(log_dir),
        "--allow-capture-exit-code",
        "124",
        "--exec-timeout-seconds",
        str(capture_seconds),
        "--exec",
        "xcrun",
        "devicectl",
        "device",
        "process",
        "launch",
        "--device",
        device,
        "--terminate-existing",
        "--console",
        "app.roana.ios",
        "--roana-enable-corridor",
        "--roana-debug-fail-safe-stop",
    ]


def physical_commands(
    *,
    team_id: str,
    device: str,
    log_dir: Path,
    derived_data_path: Path,
    capture_seconds: float,
) -> list[list[str]]:
    return [
        build_command(team_id=team_id, device=device, derived_data_path=derived_data_path),
        install_command(device=device, app_path=app_path(derived_data_path=derived_data_path)),
        capture_command(device=device, log_dir=log_dir, capture_seconds=capture_seconds),
    ]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="A85B7E8D-1EDD-573F-9C50-BC76B9FB8E03")
    parser.add_argument("--log-dir", type=Path, default=REPO_ROOT / "logs")
    parser.add_argument("--derived-data-path", type=Path, default=DERIVED_DATA_PATH)
    parser.add_argument("--capture-seconds", type=float, default=75.0)
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    team_id = os.environ.get("ROANA_IOS_DEVELOPMENT_TEAM", "").strip()
    if not team_id:
        return json_result(
            status="blocked",
            missing=["ROANA_IOS_DEVELOPMENT_TEAM"],
            message="Set ROANA_IOS_DEVELOPMENT_TEAM in the environment; do not commit the team ID.",
        )

    missing: list[str] = []
    asset_status, asset_output = run([str(ASSET_CHECKER), "--require-present"])
    if asset_status != 0:
        missing.append("model_assets")

    device_missing = verify_ios_device_log.host_readiness(
        require_device=True,
        skip_host_checks=False,
        target_identifier=args.device,
    )
    missing.extend(device_missing)

    if missing:
        details: dict[str, object] = {"assetCheck": asset_output, "deviceMissing": device_missing}
        if args.dry_run:
            details["commands"] = physical_commands(
                team_id=team_id,
                device=args.device,
                log_dir=args.log_dir,
                derived_data_path=args.derived_data_path,
                capture_seconds=args.capture_seconds,
            )
        return json_result(
            status="blocked",
            missing=sorted(set(missing)),
            message="iOS V0b physical run prerequisites are not ready.",
            details=details,
        )

    commands = physical_commands(
        team_id=team_id,
        device=args.device,
        log_dir=args.log_dir,
        derived_data_path=args.derived_data_path,
        capture_seconds=args.capture_seconds,
    )
    if args.dry_run:
        return json_result(
            status="passed",
            missing=[],
            message="Dry run only; commands were not executed.",
            details={"commands": commands},
        )

    for index, command in enumerate(commands):
        status, output = run(command)
        if status != 0:
            return json_result(
                status="failed",
                missing=["command_failed"],
                message="iOS V0b physical command failed.",
                details={"command": command, "output": output},
            )
        if index == 0:
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
                        missing=["codesign_failed"],
                        message="iOS V0b physical app re-sign failed after materializing model assets.",
                        details={
                            "output": resign_output,
                            "materializedModelAssets": materialized_assets,
                        },
                    )

    return json_result(
        status="passed",
        missing=[],
        message="iOS V0b physical gate passed.",
    )


if __name__ == "__main__":
    raise SystemExit(main())
