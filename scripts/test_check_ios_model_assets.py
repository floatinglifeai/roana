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
                        "expectedInput": {"width": 640, "height": 640},
                        "expectedOutputs": ["VNRecognizedObjectObservation"],
                    },
                    {
                        "id": "depth-anything-v2-small",
                        "resourceName": "DepthAnythingV2Small",
                        "acceptedExtensions": ["mlmodelc", "mlpackage"],
                        "runtime": "DepthAnythingRunner",
                        "source": "test",
                        "expectedInput": {"width": 518, "height": 518},
                        "expectedOutputs": ["MLMultiArray"],
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
            self.assertEqual(details["missing"], ["yolo11n", "depth-anything-v2-small"])

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

    def test_manifest_contract_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "manifest.json"
            write_manifest(manifest)
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["models"][1]["expectedInput"]["height"] = 392
            manifest.write_text(json.dumps(data), encoding="utf-8")

            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--manifest", str(manifest)],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            details = json.loads(result.stdout)
            self.assertEqual(details["status"], "invalid")
            self.assertIn("models[1].expectedInput={'width': 518, 'height': 518}", details["errors"])


if __name__ == "__main__":
    unittest.main()
