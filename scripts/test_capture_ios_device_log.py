#!/usr/bin/env python3
"""Tests for the iOS log capture helper."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("capture-ios-device-log.py")


def fake_s0_log() -> str:
    lines = [
        "roana_ios_lifecycle camera_authorization state=authorized",
        "roana_ios_lifecycle camera_started",
        "roana_ios_model_mode value=disabled",
        "roana_ios_lifecycle camera_output_orientation interface=portrait angle=90 vision=right",
        "roana_ios_orientation source=preview interface=portrait angle=90 vision=right",
        "roana_ios_lifecycle idle_timer_disabled value=true",
    ]
    for index in range(120):
        lines.append(
            "roana_ios_frame_stats "
            "width=1280 height=720 pixel_format=420YpCbCr8BiPlanarFullRange "
            f"interval_ms=33.30 p50_ms=33.30 p95_ms=34.00 dropped=0 backlog=0 "
            f"thermal=nominal run_s=60.00 frame={index}"
        )
    lines.extend(
        [
            "roana_ios_lifecycle idle_timer_disabled value=false",
            "roana_ios_lifecycle camera_background_stop phase=background",
            "roana_ios_lifecycle camera_started",
        ],
    )
    return "\n".join(lines) + "\n"


def fake_denied_log() -> str:
    return "\n".join(
        [
            "roana_ios_model_mode value=disabled",
            "roana_ios_lifecycle camera_authorization state=denied",
            "roana_ios_lifecycle camera_permission_denied state=denied",
        ],
    ) + "\n"


class CaptureIosDeviceLogTest(unittest.TestCase):
    def run_capture(self, *extra_args: str, log_text: str = "") -> tuple[int, dict[str, object]]:
        with tempfile.TemporaryDirectory() as tmp:
            command = [
                sys.executable,
                str(SCRIPT),
                "--log-dir",
                str(Path(tmp) / "logs"),
                "--timestamp",
                "20260530T010203Z",
                "--skip-host-checks",
                "--require-device",
                "0",
                *extra_args,
            ]
            result = subprocess.run(
                command,
                input=log_text,
                check=False,
                capture_output=True,
                text=True,
            )
            return result.returncode, json.loads(result.stdout)

    def test_captures_s0_stdin_to_canonical_artifact_and_verifies(self) -> None:
        status, details = self.run_capture("--gate", "s0", log_text=fake_s0_log())

        self.assertEqual(status, 0)
        self.assertEqual(details["status"], "passed")
        self.assertEqual(details["gate"], "s0")
        artifact = Path(str(details["artifact"]))
        self.assertEqual("ios-skeleton-20260530T010203Z.log", artifact.name)

    def test_captures_denied_log_from_file_to_canonical_artifact_and_verifies(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "raw.log"
            source.write_text(fake_denied_log(), encoding="utf-8")
            command = [
                sys.executable,
                str(SCRIPT),
                "--gate",
                "s0-denied",
                "--from-file",
                str(source),
                "--log-dir",
                str(Path(tmp) / "logs"),
                "--timestamp",
                "20260530T010203Z",
                "--skip-host-checks",
                "--require-device",
                "0",
            ]
            result = subprocess.run(command, check=False, capture_output=True, text=True)

        details = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(details["status"], "passed")
        self.assertEqual("ios-permission-denied-20260530T010203Z.log", Path(str(details["artifact"])).name)

    def test_reports_missing_source_when_stdin_is_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            command = [
                sys.executable,
                str(SCRIPT),
                "--log-dir",
                str(Path(tmp) / "logs"),
            ]
            result = subprocess.run(command, input="", check=False, capture_output=True, text=True)

        details = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(details["status"], "failed")
        self.assertIn("log_source", details["missing"])


if __name__ == "__main__":
    unittest.main()
