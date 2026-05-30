#!/usr/bin/env python3
"""Capture a canonical iOS log artifact and run the matching verifier gate."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
VERIFIER = REPO_ROOT / "scripts/verify-ios-device-log.py"
ARTIFACT_PREFIX = {
    "s0": "ios-skeleton",
    "s0-denied": "ios-permission-denied",
    "v0a": "ios-v0a",
    "v0b": "ios-v0b",
}


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def artifact_path(*, log_dir: Path, gate: str, requested_timestamp: str) -> Path:
    return log_dir / f"{ARTIFACT_PREFIX[gate]}-{requested_timestamp}.log"


def read_source(args: argparse.Namespace) -> tuple[int, str, str]:
    if args.from_file is not None:
        text = args.from_file.read_text(encoding="utf-8")
        if not text:
            return 1, "", f"{args.from_file} is empty."
        return 0, text, ""

    if args.exec_command:
        command = args.exec_command
        if command and command[0] == "--":
            command = command[1:]
        completed = subprocess.run(command, check=False, capture_output=True, text=True)
        text = completed.stdout + completed.stderr
        if not text:
            return completed.returncode, "", "Capture command produced no log text."
        return completed.returncode, text, ""

    if sys.stdin.isatty():
        return 1, "", "Provide log text on stdin, --from-file, or --exec."
    text = sys.stdin.read()
    if not text:
        return 1, "", "Captured log text is empty."
    return 0, text, ""


def write_capture_failure(
    *,
    gate: str,
    artifact: Path | None,
    missing: list[str],
    message: str,
    capture_status: int,
) -> int:
    print(
        json.dumps(
            {
                "status": "failed",
                "gate": gate,
                "artifact": "" if artifact is None else str(artifact),
                "missing": missing,
                "capture_status": capture_status,
                "message": message,
            },
            indent=2,
            sort_keys=True,
        ),
    )
    return 1


def run_verifier(args: argparse.Namespace, artifact: Path) -> int:
    command = [
        str(VERIFIER),
        "--gate",
        args.gate,
        "--log",
        str(artifact),
    ]
    if args.skip_host_checks:
        command.append("--skip-host-checks")
    if args.require_device is not None:
        command.extend(["--require-device", args.require_device])
    if args.require_model_assets is not None:
        command.extend(["--require-model-assets", args.require_model_assets])
    command.extend(args.verifier_arg)

    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    return completed.returncode


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gate", choices=tuple(ARTIFACT_PREFIX), default="s0")
    parser.add_argument("--log-dir", type=Path, default=REPO_ROOT / "logs")
    parser.add_argument("--timestamp", default=timestamp())
    parser.add_argument("--from-file", type=Path)
    parser.add_argument(
        "--allow-capture-exit-code",
        action="append",
        type=int,
        default=[0],
        help="Exit code accepted from --exec capture command. Repeat for timeout-style commands.",
    )
    parser.add_argument("--skip-host-checks", action="store_true")
    parser.add_argument("--require-device", choices=("0", "1"))
    parser.add_argument("--require-model-assets", choices=("0", "1"))
    parser.add_argument(
        "--verifier-arg",
        action="append",
        default=[],
        help="Additional argument forwarded to verify-ios-device-log.py. Repeat once per token.",
    )
    parser.add_argument(
        "--exec",
        dest="exec_command",
        nargs=argparse.REMAINDER,
        help="Command that writes iOS log text to stdout/stderr. Put this option last.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.from_file is not None and args.exec_command:
        return write_capture_failure(
            gate=args.gate,
            artifact=None,
            missing=["log_source"],
            message="Use either --from-file or --exec, not both.",
            capture_status=1,
        )

    artifact = artifact_path(log_dir=args.log_dir, gate=args.gate, requested_timestamp=args.timestamp)
    capture_status, text, error = read_source(args)
    if error:
        return write_capture_failure(
            gate=args.gate,
            artifact=None,
            missing=["log_source"],
            message=error,
            capture_status=capture_status,
        )

    artifact.parent.mkdir(parents=True, exist_ok=True)
    artifact.write_text(text, encoding="utf-8")
    if capture_status not in set(args.allow_capture_exit_code):
        return write_capture_failure(
            gate=args.gate,
            artifact=artifact,
            missing=["capture_command"],
            message=f"Capture command exited {capture_status}.",
            capture_status=capture_status,
        )

    if shutil.which(str(VERIFIER)) is None and not VERIFIER.is_file():
        return write_capture_failure(
            gate=args.gate,
            artifact=artifact,
            missing=["verify_ios_device_log"],
            message="verify-ios-device-log.py is missing.",
            capture_status=0,
        )
    return run_verifier(args, artifact)


if __name__ == "__main__":
    raise SystemExit(main())
