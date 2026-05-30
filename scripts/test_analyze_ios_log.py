#!/usr/bin/env python3
"""Offline regression tests for scripts/analyze-ios-log.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ANALYZER = Path(__file__).with_name("analyze-ios-log.py")


def fake_log(
    *,
    frame_count: int,
    backlog: int = 0,
    dropped: int = 0,
    include_yolo: bool = False,
    include_yolo_description: bool = False,
    include_depth: bool = False,
    include_depth_description: bool = False,
    include_corridor: bool = False,
    include_speech: bool = False,
    include_inference: bool = False,
    inference_skipped: int = 0,
    include_orientation: bool = False,
    include_background_stop: bool = False,
    include_permission: bool = True,
) -> str:
    lines: list[str] = []
    if include_permission:
        lines.append("roana_ios_lifecycle camera_authorization state=authorized")
    lines.append("roana_ios_lifecycle camera_started")
    if include_orientation:
        lines.append("roana_ios_lifecycle camera_output_orientation angle=90")
        lines.append("roana_ios_orientation source=preview interface=portrait angle=90")
    for index in range(frame_count):
        lines.append(
            "roana_ios_frame_stats "
            f"width=1280 height=720 pixel_format=420YpCbCr8BiPlanarFullRange "
            f"interval_ms=33.30 p50_ms=33.30 p95_ms=34.00 dropped={dropped} "
            f"backlog={backlog} thermal=nominal frame={index}"
        )
    if include_yolo:
        if include_inference:
            lines.append("roana_ios_inference status=scheduled frame_id=1")
        lines.append(
            "roana_ios_yolo status=ready elapsed_ms=12.00 label=person "
            "score=0.91 center_x=0.50 center_y=0.80 width=0.20 height=0.30"
        )
        if include_inference:
            if inference_skipped:
                lines.append(
                    "roana_ios_inference status=skipped "
                    f"reason=busy skipped={inference_skipped}"
                )
            lines.append(
                "roana_ios_inference status=finished "
                f"frame_id=1 completed=1 skipped={inference_skipped}"
        )
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


class AnalyzeIosLogTest(unittest.TestCase):
    def run_analyzer(self, log_text: str, *extra_args: str) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "ios.log"
            log_path.write_text(log_text, encoding="utf-8")
            command = [sys.executable, str(ANALYZER), "--log", str(log_path), *extra_args]
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            return json.loads(result.stdout)

    def test_s0_gate_passes_with_frame_stats_and_background_stop(self) -> None:
        data = self.run_analyzer(
            fake_log(frame_count=120, include_background_stop=True),
            "--require-background-stop",
            "1",
        )

        self.assertEqual("passed", data["status"])
        self.assertEqual([], data["missing"])
        self.assertEqual(120, data["details"]["frame_stats_count"])
        self.assertTrue(data["details"]["camera_background_stop"])

    def test_v0a_v0b_gate_passes_with_model_and_feedback_evidence(self) -> None:
        data = self.run_analyzer(
            fake_log(
                frame_count=120,
                include_orientation=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_speech=True,
                include_inference=True,
            ),
            "--require-yolo",
            "1",
            "--require-yolo-description",
            "1",
            "--require-depth",
            "1",
            "--require-depth-description",
            "1",
            "--require-corridor",
            "1",
            "--require-speech",
            "1",
            "--require-orientation",
            "1",
            "--require-inference",
            "1",
        )

        self.assertEqual("passed", data["status"])
        self.assertEqual([], data["missing"])
        self.assertEqual(1, data["details"]["yolo_ok_count"])
        self.assertEqual(1, data["details"]["yolo_description_count"])
        self.assertEqual(1, data["details"]["depth_ok_count"])
        self.assertEqual(1, data["details"]["depth_description_count"])
        self.assertEqual(1, data["details"]["corridor_count"])
        self.assertEqual(1, data["details"]["preview_orientation_count"])
        self.assertEqual(1, data["details"]["capture_orientation_count"])
        self.assertEqual(1, data["details"]["inference_finished_count"])

    def test_reports_missing_model_and_feedback_evidence(self) -> None:
        data = self.run_analyzer(
            fake_log(frame_count=2, include_permission=False),
            "--min-frame-stats",
            "5",
            "--require-yolo",
            "1",
            "--require-yolo-description",
            "1",
            "--require-depth",
            "1",
            "--require-depth-description",
            "1",
            "--require-corridor",
            "1",
            "--require-speech",
            "1",
            "--require-orientation",
            "1",
            "--require-inference",
            "1",
            "--require-background-stop",
            "1",
        )

        self.assertEqual("blocked", data["status"])
        self.assertEqual(
            {
                "frame_stats>=5",
                "camera_permission_state",
                "camera_background_stop",
                "yolo_inference",
                "yolo_model_description",
                "depth_inference",
                "depth_model_description",
                "corridor_decision",
                "speech_queued",
                "preview_orientation",
                "capture_orientation",
                "inference_finished",
                "corridor_guidance_feedback",
                "corridor_stop_feedback",
            },
            set(data["missing"]),
        )

    def test_reports_backlog_and_dropped_frames(self) -> None:
        data = self.run_analyzer(fake_log(frame_count=120, backlog=1, dropped=2))

        self.assertEqual("blocked", data["status"])
        self.assertEqual({"backlog<=0", "dropped<=0"}, set(data["missing"]))

    def test_reports_excessive_inference_skips(self) -> None:
        data = self.run_analyzer(
            fake_log(
                frame_count=120,
                include_yolo=True,
                include_inference=True,
                inference_skipped=3,
            ),
            "--require-inference",
            "1",
            "--max-inference-skipped",
            "2",
        )

        self.assertEqual("blocked", data["status"])
        self.assertIn("inference_skipped<=2", data["missing"])
        self.assertEqual(3, data["details"]["max_inference_skipped"])

    def test_reports_missing_model_description_evidence(self) -> None:
        data = self.run_analyzer(
            fake_log(
                frame_count=120,
                include_yolo=True,
                include_depth=True,
                include_inference=True,
            ),
            "--require-yolo",
            "1",
            "--require-yolo-description",
            "1",
            "--require-depth",
            "1",
            "--require-depth-description",
            "1",
            "--require-inference",
            "1",
        )

        self.assertEqual("blocked", data["status"])
        self.assertIn("yolo_model_description", data["missing"])
        self.assertIn("depth_model_description", data["missing"])

    def test_reports_missing_orientation_evidence(self) -> None:
        data = self.run_analyzer(
            fake_log(frame_count=120),
            "--require-orientation",
            "1",
        )

        self.assertEqual("blocked", data["status"])
        self.assertIn("preview_orientation", data["missing"])
        self.assertIn("capture_orientation", data["missing"])

    def test_permission_denied_gate_passes_without_camera_start(self) -> None:
        data = self.run_analyzer(
            fake_denied_log(),
            "--min-frame-stats",
            "0",
            "--require-camera-start",
            "0",
            "--require-permission-denied",
            "1",
        )

        self.assertEqual("passed", data["status"])
        self.assertEqual([], data["missing"])
        self.assertTrue(data["details"]["permission_denied_seen"])
        self.assertTrue(data["details"]["camera_permission_denied"])

    def test_permission_denied_gate_reports_missing_denied_ui_evidence(self) -> None:
        data = self.run_analyzer(
            "roana_ios_lifecycle camera_authorization state=denied\n",
            "--min-frame-stats",
            "0",
            "--require-camera-start",
            "0",
            "--require-permission-denied",
            "1",
        )

        self.assertEqual("blocked", data["status"])
        self.assertIn("camera_permission_denied_ui", data["missing"])


if __name__ == "__main__":
    unittest.main()
