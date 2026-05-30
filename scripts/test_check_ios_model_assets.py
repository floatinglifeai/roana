#!/usr/bin/env python3
"""Tests for the iOS model asset checker."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check-ios-model-assets.py")


def write_manifest(path: Path) -> None:
    path.write_text(
        json.dumps(
            {
                "schema": 1,
                "models": [
                    {
                        "id": "yolo11n",
                        "resourceName": "YOLO11n",
                        "acceptedExtensions": ["mlmodelc", "mlpackage"],
                        "runtime": "YoloObstacleDetector",
                        "source": "test",
                    },
                    {
                        "id": "depth",
                        "resourceName": "DepthAnythingV2Small",
                        "acceptedExtensions": ["mlmodelc", "mlpackage"],
                        "runtime": "DepthAnythingRunner",
                        "source": "test",
                    },
                ],
            },
        ),
        encoding="utf-8",
    )


class CheckIosModelAssetsTest(unittest.TestCase):
    def test_missing_assets_are_reported_without_failing_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            write_manifest(manifest)

            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--manifest", str(manifest)],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0)
            details = json.loads(result.stdout)
            self.assertEqual(details["status"], "missing")
            self.assertEqual(details["missing"], ["yolo11n", "depth"])

    def test_require_present_fails_when_assets_are_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            write_manifest(manifest)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--manifest",
                    str(manifest),
                    "--require-present",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stdout)["status"], "missing")

    def test_present_assets_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.json"
            write_manifest(manifest)
            (root / "YOLO11n.mlpackage").mkdir()
            (root / "DepthAnythingV2Small.mlmodelc").mkdir()

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--manifest",
                    str(manifest),
                    "--require-present",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0)
            self.assertEqual(json.loads(result.stdout)["status"], "ready")

    def test_conflicting_extensions_fail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.json"
            write_manifest(manifest)
            (root / "YOLO11n.mlpackage").mkdir()
            (root / "YOLO11n.mlmodelc").mkdir()

            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--manifest", str(manifest)],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stdout)["status"], "invalid")


if __name__ == "__main__":
    unittest.main()
