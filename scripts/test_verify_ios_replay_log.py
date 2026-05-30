#!/usr/bin/env python3
"""Offline regression tests for scripts/verify-ios-replay-log.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


VERIFIER = Path(__file__).with_name("verify-ios-replay-log.py")


def replay_log(*, include_replay_markers: bool = True, guidance: bool = False) -> str:
    lines: list[str] = []
    if include_replay_markers:
        lines.append("roana_ios_replay status=started video=fixture.mp4 duration_s=2.00 fps=1.00 width=720 height=1280")
    lines.extend(
        [
            "roana_ios_model_mode value=corridor",
            "roana_ios_lifecycle camera_output_orientation interface=portrait angle=90 vision=right",
            "roana_ios_orientation source=preview interface=portrait angle=90 vision=right",
            (
                "roana_ios_yolo status=model_description resource=YOLO11n author=unknown "
                "version=unknown inputs=image:image_640x640 "
                "outputs=confidence:multiarray_0x80_float32,coordinates:multiarray_0x4_float32"
            ),
            (
                "roana_ios_depth status=model_description resource=DepthAnythingV2Small "
                "author=unknown version=unknown inputs=image:image_518x392 outputs=depth:image_518x392"
            ),
        ],
    )
    for index in range(3):
        lines.extend(
            [
                (
                    "roana_ios_frame_stats width=720 height=1280 "
                    "pixel_format=420YpCbCr8BiPlanarFullRange interval_ms=1000.00 "
                    "p50_ms=1000.00 p95_ms=1000.00 dropped=0 backlog=0 "
                    f"thermal=nominal run_s={index:.2f}"
                ),
                (
                    "roana_ios_yolo status=ready elapsed_ms=6.00 vision=right "
                    "label=chair score=0.72 center_x=0.29 center_y=0.81 width=0.36 height=0.38"
                ),
                "roana_ios_depth status=ok elapsed_ms=88.00 vision=right grid_rows=15 grid_cols=15",
            ],
        )
    if guidance:
        lines.extend(
            [
                (
                    "roana_ios_corridor decision=STRAIGHT state=STRAIGHT reason=path_found "
                    "path_cells=15 pending=none pending_count=0"
                ),
                "roana_ios_audio_session status=active category=playback mode=spokenAudio options=duckOthers",
                (
                    "roana_ios_corridor_feedback status=spoken id=guidance-1 command=STRAIGHT "
                    "message=go_straight reason=path_found changed=true forced=false "
                    "pending=none pending_count=0"
                ),
            ],
        )
    lines.extend(
        [
            (
                "roana_ios_corridor decision=STOP state=STOP reason=near_obstacle "
                "path_cells=0 pending=none pending_count=0"
            ),
            (
                "roana_ios_corridor_feedback status=spoken id=stop-1 command=STOP "
                "message=stop reason=near_obstacle changed=false forced=false "
                "pending=none pending_count=0"
            ),
        ],
    )
    if include_replay_markers:
        lines.append("roana_ios_replay status=finished frames=3")
    return "\n".join(lines) + "\n"


class VerifyIosReplayLogTest(unittest.TestCase):
    def run_verifier(self, log_text: str, *extra_args: str, check: bool = True) -> tuple[int, dict[str, object]]:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "replay.log"
            log_path.write_text(log_text, encoding="utf-8")
            command = [sys.executable, str(VERIFIER), "--log", str(log_path), *extra_args]
            result = subprocess.run(command, check=False, capture_output=True, text=True)
            if check:
                self.assertEqual("", result.stderr)
                self.assertEqual(0, result.returncode, result.stdout)
            return result.returncode, json.loads(result.stdout)

    def test_stop_fixture_passes_without_audio_or_guidance(self) -> None:
        status, data = self.run_verifier(replay_log())

        self.assertEqual(0, status)
        self.assertEqual("passed", data["status"])
        self.assertEqual("stop", data["fixture"])
        self.assertEqual([], data["missing"])
        self.assertEqual(0, data["analysis"]["details"]["audio_session_active_count"])
        self.assertEqual("", data["analysis"]["details"]["normal_corridor_feedback"])

    def test_guidance_fixture_requires_audio_and_normal_guidance(self) -> None:
        status, data = self.run_verifier(replay_log(guidance=True), "--fixture", "guidance")

        self.assertEqual(0, status)
        self.assertEqual("passed", data["status"])
        self.assertIn("command=STRAIGHT", data["analysis"]["details"]["normal_corridor_feedback"])
        self.assertEqual(1, data["analysis"]["details"]["audio_session_active_count"])

    def test_guidance_fixture_reports_missing_audio_and_guidance(self) -> None:
        status, data = self.run_verifier(replay_log(), "--fixture", "guidance", check=False)

        self.assertEqual(2, status)
        self.assertEqual("blocked", data["status"])
        self.assertIn("audio_session_active", data["missing"])
        self.assertIn("corridor_guidance_feedback", data["missing"])

    def test_reports_missing_replay_markers(self) -> None:
        status, data = self.run_verifier(replay_log(include_replay_markers=False), check=False)

        self.assertEqual(2, status)
        self.assertEqual("blocked", data["status"])
        self.assertIn("replay_started", data["missing"])
        self.assertIn("replay_finished", data["missing"])


if __name__ == "__main__":
    unittest.main()
