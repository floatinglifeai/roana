#!/usr/bin/env python3
"""Tests for the portable iOS privacy boundary verifier."""

from __future__ import annotations

import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SWIFT_SOURCE = ROOT / "ios" / "Roana" / "RoanaTests" / "Privacy" / "main.swift"


class IosPrivacyBoundaryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmp = tempfile.TemporaryDirectory()
        cls.binary = Path(cls._tmp.name) / "privacy-boundary"
        subprocess.run(
            ["swiftc", str(SWIFT_SOURCE), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def write_fixture(
        self,
        root: Path,
        *,
        plist_extra: dict[str, object] | None = None,
        source_name: str = "Safe.swift",
        source: str = "struct SafeCameraOnlyCode {}\n",
    ) -> None:
        source_root = root / "ios" / "Roana" / "Roana"
        source_root.mkdir(parents=True)
        values = {
            "CFBundleIdentifier": "com.roana.test",
            "NSCameraUsageDescription": "Camera frames stay on device.",
        }
        if plist_extra is not None:
            values.update(plist_extra)
        with (source_root / "Info.plist").open("wb") as handle:
            plistlib.dump(values, handle)
        (source_root / source_name).write_text(source, encoding="utf-8")

    def run_boundary(self, root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.binary), str(root)],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_camera_only_fixture_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fixture(root)

            result = self.run_boundary(root)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PrivacyBoundary passed", result.stdout)

    def test_forbidden_source_reports_relative_file_and_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fixture(
                root,
                source_name="NetworkLeak.swift",
                source="// line 1\nstruct NetworkLeak {\n    let token = \"URLSession\"\n}\n",
            )

            result = self.run_boundary(root)

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "Forbidden network_or_frame_storage token found: URLSession at NetworkLeak.swift:3",
            result.stderr,
        )

    def test_forbidden_framework_import_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fixture(
                root,
                source_name="LocationLeak.swift",
                source="import CoreLocation\nstruct LocationLeak {}\n",
            )

            result = self.run_boundary(root)

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "Forbidden out_of_scope_guidance_or_identity token found: import CoreLocation at LocationLeak.swift:1",
            result.stderr,
        )

    def test_forbidden_info_plist_key_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write_fixture(root, plist_extra={"NSLocationWhenInUseUsageDescription": "not in V0"})

            result = self.run_boundary(root)

        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "Forbidden Info.plist keys for iOS V0 privacy boundary: NSLocationWhenInUseUsageDescription",
            result.stderr,
        )


if __name__ == "__main__":
    unittest.main()
