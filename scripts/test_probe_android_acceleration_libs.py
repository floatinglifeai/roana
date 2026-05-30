#!/usr/bin/env python3
"""Offline tests for scripts/probe-android-acceleration-libs.py."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROBE = Path(__file__).with_name("probe-android-acceleration-libs.py")


def load_probe_module():
    spec = importlib.util.spec_from_file_location("probe_android_acceleration_libs", PROBE)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load probe module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def metadata_xml(
    *,
    latest: str = "1.2.3",
    release: str = "1.2.3",
    versions: list[str] | None = None,
    last_updated: str = "20260530000000",
) -> str:
    versions = versions or ["1.0.0", "1.2.0", latest]
    version_lines = "\n".join(f"      <version>{version}</version>" for version in versions)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <versioning>
    <latest>{latest}</latest>
    <release>{release}</release>
    <versions>
{version_lines}
    </versions>
    <lastUpdated>{last_updated}</lastUpdated>
  </versioning>
</metadata>
"""


class AndroidAccelerationProbeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.probe = load_probe_module()

    def test_parse_metadata_extracts_latest_and_recent_versions(self) -> None:
        metadata = self.probe.parse_metadata(
            metadata_xml(
                latest="2.1.5",
                release="2.1.5",
                versions=["2.0.0", "2.1.0", "2.1.5"],
                last_updated="20260515235240",
            )
        )

        self.assertEqual("2.1.5", metadata.latest)
        self.assertEqual("2.1.5", metadata.release)
        self.assertEqual(["2.0.0", "2.1.0", "2.1.5"], metadata.versions)
        self.assertEqual("20260515235240", metadata.last_updated)

    def test_parse_metadata_falls_back_to_last_version_when_latest_missing(self) -> None:
        metadata = self.probe.parse_metadata(
            """<metadata><versioning><versions><version>1.0.0</version><version>1.1.0</version></versions></versioning></metadata>"""
        )

        self.assertEqual("1.1.0", metadata.latest)
        self.assertEqual("", metadata.release)

    def test_build_report_passes_when_all_candidates_resolve(self) -> None:
        def fetcher(url: str, timeout_seconds: int) -> str:
            return metadata_xml(latest="9.9.9")

        report = self.probe.build_report(fetcher=fetcher)

        self.assertEqual("passed", report["status"])
        self.assertEqual(4, len(report["artifacts"]))
        self.assertTrue(all(result["latest"] == "9.9.9" for result in report["artifacts"]))
        self.assertIn("Keep the passing QNN HTP delegate", report["decision"])

    def test_decision_blocks_migration_when_litert_metadata_is_missing(self) -> None:
        results = [
            {"artifact": "litert", "status": "unavailable"},
            {"artifact": "onnxruntime-android-qnn", "status": "available"},
            {"artifact": "executorch-android", "status": "available"},
        ]

        self.assertIn("do not start a migration spike", self.probe.decision(results))

    def test_decision_uses_litert_when_ort_qnn_is_missing(self) -> None:
        results = [
            {"artifact": "litert", "status": "available"},
            {"artifact": "onnxruntime-android-qnn", "status": "unavailable"},
            {"artifact": "executorch-android", "status": "available"},
        ]

        self.assertIn("use LiteRT as the only near-term alternative", self.probe.decision(results))

    def test_decision_defers_executorch_when_only_executorch_is_missing(self) -> None:
        results = [
            {"artifact": "litert", "status": "available"},
            {"artifact": "onnxruntime-android-qnn", "status": "available"},
            {"artifact": "executorch-android", "status": "unavailable"},
        ]

        self.assertIn("keep it deferred", self.probe.decision(results))

    def test_cli_writes_json_output(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "probe.json"
            result = subprocess.run(
                [sys.executable, str(PROBE), "--output", str(output)],
                check=True,
                capture_output=True,
                text=True,
            )

            stdout_report = json.loads(result.stdout)
            file_report = json.loads(output.read_text(encoding="utf-8"))

            self.assertEqual(stdout_report["status"], file_report["status"])
            self.assertEqual(4, len(file_report["artifacts"]))


if __name__ == "__main__":
    unittest.main()
