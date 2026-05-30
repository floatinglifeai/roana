#!/usr/bin/env python3
"""Tests for the iOS V0b physical-run helper."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("run-ios-v0b-physical.py")
spec = importlib.util.spec_from_file_location("run_ios_v0b_physical", SCRIPT)
assert spec is not None
run_ios_v0b_physical = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(run_ios_v0b_physical)


class RunIosV0bPhysicalTest(unittest.TestCase):
    def test_blocks_without_team_id(self) -> None:
        env = os.environ.copy()
        env.pop("ROANA_IOS_DEVELOPMENT_TEAM", None)
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--dry-run"],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(2, result.returncode)
        details = json.loads(result.stdout)
        self.assertEqual("blocked", details["status"])
        self.assertIn("ROANA_IOS_DEVELOPMENT_TEAM", details["missing"])
        self.assertNotIn("DEVELOPMENT_TEAM=", result.stdout)

    def test_dry_run_with_team_does_not_report_log_file_prerequisite(self) -> None:
        env = os.environ.copy()
        env["ROANA_IOS_DEVELOPMENT_TEAM"] = "TEAM123"
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--dry-run"],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

        details = json.loads(result.stdout)
        self.assertNotIn("log_file", details["missing"])

    def test_build_command_uses_command_line_team(self) -> None:
        command = run_ios_v0b_physical.build_command(
            team_id="TEAM123",
            device="DEVICE123",
            derived_data_path=Path("/tmp/derived"),
        )

        self.assertIn("DEVELOPMENT_TEAM=TEAM123", command)
        self.assertIn("-derivedDataPath", command)
        self.assertIn("/tmp/derived", command)
        self.assertIn("-allowProvisioningUpdates", command)
        self.assertIn("Roana-V0b-Corridor", command)
        self.assertNotIn("XP2NFR9M33", " ".join(command))

    def test_app_path_uses_runner_derived_data(self) -> None:
        app_path = run_ios_v0b_physical.app_path(derived_data_path=Path("/tmp/derived"))

        self.assertEqual(Path("/tmp/derived/Build/Products/Debug-iphoneos/Roana.app"), app_path)

    def test_capture_command_launches_corridor_mode(self) -> None:
        command = run_ios_v0b_physical.capture_command(
            device="DEVICE123",
            log_dir=Path("/tmp/roana-logs"),
            capture_seconds=75.0,
        )

        self.assertIn("capture-ios-device-log.py", command[0])
        self.assertIn("--gate", command)
        self.assertIn("v0b", command)
        self.assertIn("--allow-capture-exit-code", command)
        self.assertIn("124", command)
        self.assertIn("--exec-timeout-seconds", command)
        self.assertIn("75.0", command)
        self.assertIn("app.roana.ios", command)
        self.assertIn("--roana-enable-corridor", command)
        self.assertIn("--roana-debug-fail-safe-stop", command)


if __name__ == "__main__":
    unittest.main()
