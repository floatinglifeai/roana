#!/usr/bin/env python3
"""Tests for the iOS physical-device log verifier."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("verify-ios-device-log.py")


def fake_log(
    *,
    frame_count: int,
    include_yolo: bool = False,
    include_yolo_description: bool = False,
    include_depth: bool = False,
    include_depth_description: bool = False,
    include_corridor: bool = False,
    include_speech: bool = False,
    include_inference: bool = False,
    include_orientation: bool = False,
    include_background_stop: bool = False,
) -> str:
    lines = [
        "roana_ios_lifecycle camera_authorization state=authorized",
        "roana_ios_lifecycle camera_started",
    ]
    if include_orientation:
        lines.append("roana_ios_lifecycle camera_output_orientation angle=90")
        lines.append("roana_ios_orientation source=preview interface=portrait angle=90")
    for index in range(frame_count):
        lines.append(
            "roana_ios_frame_stats "
            "width=1280 height=720 pixel_format=420YpCbCr8BiPlanarFullRange "
            f"interval_ms=33.30 p50_ms=33.30 p95_ms=34.00 dropped=0 backlog=0 "
            f"thermal=nominal frame={index}"
        )
    if include_yolo:
        if include_inference:
            lines.append("roana_ios_inference status=scheduled frame_id=1")
        lines.append(
            "roana_ios_yolo status=ready elapsed_ms=12.00 label=person "
            "score=0.91 center_x=0.50 center_y=0.80 width=0.20 height=0.30"
        )
        if include_inference:
            lines.append("roana_ios_inference status=finished frame_id=1 completed=1 skipped=0")
    if include_yolo_description:
        lines.append(
            "roana_ios_yolo status=model_description resource=YOLO11n "
            "author=unknown version=unknown inputs=image:image_640x640 "
            "outputs=coordinates:multiarray_1x100x4_float32,confidence:multiarray_1x100x80_float32"
        )
    if include_depth:
        lines.append("roana_ios_depth status=ok elapsed_ms=31.00 grid_rows=15 grid_cols=15")
    if include_depth_description:
        lines.append(
            "roana_ios_depth status=model_description resource=DepthAnythingV2Small "
            "author=unknown version=unknown inputs=image:image_518x518 "
            "outputs=depth:multiarray_1x1x518x518_float32"
        )
    if include_corridor:
        lines.append(
            "roana_ios_corridor decision=STRAIGHT state=STRAIGHT "
            "reason=path_found path_cells=15 pending=none pending_count=0"
        )
        lines.append(
            "roana_ios_corridor_feedback status=spoken id=guidance-1 "
            "command=STRAIGHT message=go_straight reason=path_found "
            "changed=true forced=false pending=none pending_count=0"
        )
        lines.append(
            "roana_ios_corridor_feedback status=spoken id=stop-1 "
            "command=STOP message=stop reason=low_confidence "
            "changed=true forced=false pending=none pending_count=0"
        )
    if include_speech:
        lines.append("roana_ios_speech status=queued label=person score=91 message=Person_ahead")
    if include_background_stop:
        lines.append("roana_ios_lifecycle camera_background_stop phase=background")
    return "\n".join(lines) + "\n"


def fake_denied_log() -> str:
    return "\n".join(
        [
            "roana_ios_lifecycle camera_authorization state=denied",
            "roana_ios_lifecycle camera_permission_denied state=denied",
        ],
    ) + "\n"


class VerifyIosDeviceLogTest(unittest.TestCase):
    def run_verifier(self, log_text: str, *extra_args: str) -> tuple[int, dict[str, object]]:
        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "ios.log"
            log_path.write_text(log_text, encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--log",
                    str(log_path),
                    "--skip-host-checks",
                    "--require-device",
                    "0",
                    *extra_args,
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            return result.returncode, json.loads(result.stdout)

    def test_s0_log_passes_without_model_assets(self) -> None:
        status, details = self.run_verifier(
            fake_log(frame_count=120, include_orientation=True, include_background_stop=True),
            "--gate",
            "s0",
        )

        self.assertEqual(status, 0)
        self.assertEqual(details["status"], "passed")
        self.assertEqual(details["missing"], [])

    def test_v0a_defaults_require_model_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(frame_count=120, include_background_stop=True),
            "--gate",
            "v0a",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("yolo_inference", details["missing"])
        self.assertIn("yolo_model_description", details["missing"])
        self.assertIn("speech_queued", details["missing"])
        self.assertIn("preview_orientation", details["missing"])
        self.assertIn("capture_orientation", details["missing"])
        self.assertIn("inference_finished", details["missing"])

    def test_v0b_log_passes_with_model_corridor_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_orientation=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_speech=True,
                include_inference=True,
            ),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 0)
        self.assertEqual(details["status"], "passed")

    def test_v0b_defaults_require_model_descriptions(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_orientation=True,
                include_yolo=True,
                include_depth=True,
                include_corridor=True,
                include_speech=True,
                include_inference=True,
            ),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("yolo_model_description", details["missing"])
        self.assertIn("depth_model_description", details["missing"])

    def test_s0_defaults_require_orientation_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(frame_count=120, include_background_stop=True),
            "--gate",
            "s0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("preview_orientation", details["missing"])
        self.assertIn("capture_orientation", details["missing"])

    def test_s0_denied_gate_passes_without_camera_start_or_frames(self) -> None:
        status, details = self.run_verifier(
            fake_denied_log(),
            "--gate",
            "s0-denied",
        )

        self.assertEqual(status, 0)
        self.assertEqual(details["status"], "passed")
        self.assertEqual(details["missing"], [])

    def test_s0_denied_gate_requires_denied_ui_evidence(self) -> None:
        status, details = self.run_verifier(
            "roana_ios_lifecycle camera_authorization state=denied\n",
            "--gate",
            "s0-denied",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("camera_permission_denied_ui", details["missing"])

    def test_missing_log_file_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--log",
                    str(Path(tmp) / "missing.log"),
                    "--skip-host-checks",
                    "--require-device",
                    "0",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 2)
            self.assertIn("log_file", json.loads(result.stdout)["missing"])


if __name__ == "__main__":
    unittest.main()
