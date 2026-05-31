#!/usr/bin/env python3
"""Tests for scripts/benchmark-ios-video-replay-device.py."""

from __future__ import annotations

import importlib.util
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("benchmark-ios-video-replay-device.py")
spec = importlib.util.spec_from_file_location("benchmark_ios_video_replay_device", SCRIPT)
assert spec is not None
benchmark_ios = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(benchmark_ios)


class BenchmarkIosVideoReplayDeviceTest(unittest.TestCase):
    def test_launch_command_uses_replay_arguments(self) -> None:
        command = benchmark_ios.launch_command(
            device="DEVICE123",
            video_name="iphone_0530.mp4",
            fps=10.0,
            max_seconds=None,
        )

        self.assertEqual(["xcrun", "devicectl", "device", "process", "launch"], command[:5])
        self.assertIn("--console", command)
        self.assertIn("app.roana.ios", command)
        self.assertIn("--roana-enable-corridor", command)
        self.assertIn("--roana-replay-video", command)
        self.assertIn("iphone_0530.mp4", command)
        self.assertIn("--roana-replay-fps", command)
        self.assertIn("10", command)
        self.assertNotIn("--roana-debug-fail-safe-stop", command)

    def test_launch_command_includes_optional_max_seconds(self) -> None:
        command = benchmark_ios.launch_command(
            device="DEVICE123",
            video_name="clip.mp4",
            fps=5.0,
            max_seconds=12.5,
        )

        self.assertIn("--roana-replay-max-seconds", command)
        self.assertIn("12.5", command)

    def test_copy_video_command_targets_app_documents(self) -> None:
        command = benchmark_ios.copy_video_command(device="DEVICE123", source_dir=Path("/tmp/replay"))

        self.assertEqual(["xcrun", "devicectl", "device", "copy", "to"], command[:5])
        self.assertIn("--domain-type", command)
        self.assertIn("appDataContainer", command)
        self.assertIn("--domain-identifier", command)
        self.assertIn("app.roana.ios", command)
        self.assertIn("--destination", command)
        self.assertIn("Documents", command)

    def test_materializes_app_model_asset_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "target.mlmodelc"
            target.mkdir()
            (target / "model.bin").write_text("model", encoding="utf-8")
            app_assets = root / "Roana.app" / "ModelAssets"
            app_assets.mkdir(parents=True)
            link = app_assets / "Target.mlmodelc"
            link.symlink_to(target)

            materialized = benchmark_ios.materialize_app_model_asset_symlinks(root / "Roana.app")

            self.assertEqual(["Target.mlmodelc"], materialized)
            self.assertFalse(link.is_symlink())
            self.assertEqual("model", (link / "model.bin").read_text(encoding="utf-8"))

    def test_classifies_signing_failures_as_blocked(self) -> None:
        status, missing = benchmark_ios.classify_setup_failure(
            'No Account for Team "TEAM123". No profiles for \'app.roana.ios\' were found.',
        )

        self.assertEqual("blocked", status)
        self.assertIn("xcode_account", missing)
        self.assertIn("provisioning_profile", missing)

    def test_classifies_locked_device_as_blocked(self) -> None:
        status, missing = benchmark_ios.classify_setup_failure(
            "Unable to launch app.roana.ios because the device was not, or could not be, unlocked.",
        )

        self.assertEqual("blocked", status)
        self.assertIn("iphone_unlocked", missing)

    def test_classifies_model_asset_symlink_failure(self) -> None:
        status, missing = benchmark_ios.classify_setup_failure(
            "Invalid symlink: /Roana.app/ModelAssets/YOLO11n.mlmodelc -> /absolute/path",
        )

        self.assertEqual("blocked", status)
        self.assertIn("model_asset_symlink", missing)

    def test_infers_team_id_from_matching_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profile = root / "profile.mobileprovision"
            profile.write_bytes(
                plistlib.dumps(
                    {
                        "Entitlements": {"application-identifier": "TEAM123.app.roana.ios"},
                        "ProvisionedDevices": ["DEVICE123"],
                        "TeamIdentifier": ["TEAM123"],
                    },
                ),
            )
            original_dirs = benchmark_ios.PROFILE_DIRS
            original_decode = benchmark_ios.decode_mobileprovision
            try:
                benchmark_ios.PROFILE_DIRS = [root]
                benchmark_ios.decode_mobileprovision = lambda path: plistlib.loads(Path(path).read_bytes())

                team_id = benchmark_ios.infer_team_id_from_profiles(device_udid="DEVICE123")
            finally:
                benchmark_ios.PROFILE_DIRS = original_dirs
                benchmark_ios.decode_mobileprovision = original_decode

        self.assertEqual("TEAM123", team_id)

    def test_physical_commands_are_ordered(self) -> None:
        commands = benchmark_ios.physical_commands(
            team_id="TEAM123",
            device="DEVICE123",
            derived_data_path=Path("/tmp/derived"),
            source_dir=Path("/tmp/source/replay"),
            video_name="iphone_0530.mp4",
            fps=10.0,
            max_seconds=None,
        )

        self.assertEqual("xcodebuild", commands[0][0])
        self.assertEqual(["xcrun", "devicectl", "device", "install", "app"], commands[1][:5])
        self.assertEqual(["xcrun", "devicectl", "device", "copy", "to"], commands[2][:5])
        self.assertEqual(["xcrun", "devicectl", "device", "process", "launch"], commands[3][:5])

    def test_blocks_without_team_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            video = Path(tmp) / "fixture.mp4"
            video.write_text("fixture", encoding="utf-8")
            env = os.environ.copy()
            env.pop("ROANA_IOS_DEVELOPMENT_TEAM", None)
            env["PATH"] = f"{tmp}:{env.get('PATH', '')}"
            security = Path(tmp) / "security"
            security.write_text("#!/usr/bin/env sh\nexit 1\n", encoding="utf-8")
            security.chmod(0o755)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--dry-run",
                    "--skip-host-checks",
                    "--video",
                    str(video),
                    "--output-dir",
                    str(Path(tmp) / "logs"),
                ],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )

        details = json.loads(result.stdout)
        self.assertEqual(2, result.returncode)
        self.assertEqual("blocked", details["status"])
        self.assertIn("ROANA_IOS_DEVELOPMENT_TEAM", details["missing"])
        self.assertNotIn("DEVELOPMENT_TEAM=", result.stdout)

    def test_dry_run_with_team_reports_commands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            video = Path(tmp) / "fixture.mp4"
            video.write_text("fixture", encoding="utf-8")
            env = os.environ.copy()
            env["ROANA_IOS_DEVELOPMENT_TEAM"] = "TEAM123"
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--dry-run",
                    "--skip-host-checks",
                    "--video",
                    str(video),
                    "--output-dir",
                    str(Path(tmp) / "logs"),
                    "--fps",
                    "10",
                ],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )

        details = json.loads(result.stdout)
        if "model_assets" in details["missing"]:
            self.assertEqual("blocked", details["status"])
        else:
            self.assertEqual("passed", details["status"])
        self.assertEqual("environment", details["details"]["teamSource"])
        commands = details["details"]["commands"]
        self.assertIn("DEVELOPMENT_TEAM=TEAM123", commands[0])
        self.assertIn("--roana-replay-video", commands[3])


if __name__ == "__main__":
    unittest.main()
