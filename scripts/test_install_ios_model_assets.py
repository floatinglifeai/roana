#!/usr/bin/env python3
"""Tests for the iOS Core ML model asset installer."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("install-ios-model-assets.py")
CHECKER = Path(__file__).with_name("check-ios-model-assets.py")


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
                        "expectedInput": {"width": 518, "height": 392},
                        "expectedOutputs": ["MLMultiArray", "VNPixelBufferObservation"],
                    },
                ],
            },
        ),
        encoding="utf-8",
    )


class InstallIosModelAssetsTest(unittest.TestCase):
    def test_copies_source_to_manifest_resource_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.json"
            write_manifest(manifest)
            source = root / "exported-yolo.mlpackage"
            source.mkdir()
            (source / "Manifest.json").write_text("{}", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--manifest",
                    str(manifest),
                    "--model",
                    "yolo11n",
                    "--source",
                    str(source),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0)
            details = json.loads(result.stdout)
            self.assertEqual(details["status"], "installed")
            destination = root / "YOLO11n.mlpackage"
            self.assertTrue(destination.is_dir())
            self.assertTrue((destination / "Manifest.json").exists())

    def test_symlink_mode_installs_link(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.json"
            write_manifest(manifest)
            source = root / "DepthAnything.mlmodelc"
            source.mkdir()

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--manifest",
                    str(manifest),
                    "--model",
                    "DepthAnythingV2Small",
                    "--source",
                    str(source),
                    "--symlink",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0)
            self.assertTrue((root / "DepthAnythingV2Small.mlmodelc").is_symlink())

    def test_rejects_wrong_extension(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.json"
            write_manifest(manifest)
            source = root / "model.onnx"
            source.write_text("not-coreml", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--manifest",
                    str(manifest),
                    "--model",
                    "yolo11n",
                    "--source",
                    str(source),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stdout)["status"], "failed")

    def test_installed_assets_satisfy_checker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.json"
            write_manifest(manifest)
            yolo = root / "source-yolo.mlpackage"
            depth = root / "source-depth.mlmodelc"
            yolo.mkdir()
            depth.mkdir()

            for model, source in (("yolo11n", yolo), ("depth-anything-v2-small", depth)):
                subprocess.run(
                    [
                        sys.executable,
                        str(SCRIPT),
                        "--manifest",
                        str(manifest),
                        "--model",
                        model,
                        "--source",
                        str(source),
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                )

            check = subprocess.run(
                [
                    sys.executable,
                    str(CHECKER),
                    "--manifest",
                    str(manifest),
                    "--require-present",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(check.returncode, 0)
            self.assertEqual(json.loads(check.stdout)["status"], "ready")

    def test_rejects_large_copy_without_explicit_acknowledgement(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.json"
            write_manifest(manifest)
            source = root / "large-yolo.mlpackage"
            source.mkdir()
            (source / "weights.bin").write_bytes(b"0" * 2048)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--manifest",
                    str(manifest),
                    "--model",
                    "yolo11n",
                    "--source",
                    str(source),
                    "--max-copy-mb",
                    "0",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            details = json.loads(result.stdout)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(details["status"], "failed")
            self.assertIn("--allow-large-copy", details["error"])

    def test_allows_large_copy_with_explicit_acknowledgement(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.json"
            write_manifest(manifest)
            source = root / "large-yolo.mlpackage"
            source.mkdir()
            (source / "weights.bin").write_bytes(b"0" * 2048)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--manifest",
                    str(manifest),
                    "--model",
                    "yolo11n",
                    "--source",
                    str(source),
                    "--max-copy-mb",
                    "0",
                    "--allow-large-copy",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            details = json.loads(result.stdout)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(details["status"], "installed")
            self.assertEqual(2048, details["copiedBytes"])
            self.assertTrue((root / "YOLO11n.mlpackage" / "weights.bin").exists())


if __name__ == "__main__":
    unittest.main()
