#!/usr/bin/env python3
"""Tests for scripts/label-ios-replay.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("label-ios-replay.py")


def replay_log(
    *,
    decision: str = "STOP",
    reason: str = "near_obstacle",
    feedback_command: str = "STOP",
    motion_quality_line: str = (
        "roana_ios_motion_quality label=stable reason=motion_unavailable "
        "trusts_guidance=true source=replay"
    ),
) -> str:
    return "\n".join(
        [
            "roana_ios_replay status=started video=fixture.mp4 duration_s=2.00 fps=1.00 width=720 height=1280",
            "roana_ios_model_mode value=corridor",
            "roana_ios_lifecycle camera_output_orientation interface=portrait angle=90 vision=right",
            "roana_ios_orientation source=preview interface=portrait angle=90 vision=right",
            motion_quality_line,
            (
                "roana_ios_frame_stats width=720 height=1280 "
                "pixel_format=420YpCbCr8BiPlanarFullRange interval_ms=1000.00 "
                "p50_ms=1000.00 p95_ms=1000.00 dropped=0 backlog=0 "
                "thermal=nominal run_s=2.00"
            ),
            f"roana_ios_corridor decision={decision} state={decision} reason={reason} path_cells=0 pending=none pending_count=0",
            (
                f"roana_ios_corridor_feedback status=spoken id=fixture-1 command={feedback_command} "
                f"message={feedback_command.lower()} reason={reason} changed=true forced=false "
                "pending=none pending_count=0"
            ),
            "roana_ios_replay status=finished frames=1",
        ],
    ) + "\n"


class LabelIosReplayTest(unittest.TestCase):
    def run_labeler(self, log_text: str, *extra_args: str, check: bool = True) -> tuple[int, dict[str, object]]:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "replay.log"
            log_path.write_text(log_text, encoding="utf-8")
            command = [sys.executable, str(SCRIPT), "--from-log", str(log_path), *extra_args]
            result = subprocess.run(command, check=False, capture_output=True, text=True)
            if check:
                self.assertEqual("", result.stderr)
                self.assertEqual(0, result.returncode, result.stdout)
            return result.returncode, json.loads(result.stdout)

    def test_labels_stop_and_too_close(self) -> None:
        status, data = self.run_labeler(replay_log())

        self.assertEqual(0, status)
        self.assertEqual("passed", data["status"])
        self.assertEqual("stop", data["fixture_suggestion"])
        self.assertEqual(["STOP"], data["command_labels"])
        self.assertIn("too_close", data["scene_quality_labels"])
        self.assertEqual(1, data["decision_counts"]["STOP"])
        self.assertEqual(1, data["spoken_command_counts"]["STOP"])

    def test_labels_guidance(self) -> None:
        _, data = self.run_labeler(
            replay_log(decision="STRAIGHT", reason="path_found", feedback_command="STRAIGHT"),
        )

        self.assertEqual("guidance", data["fixture_suggestion"])
        self.assertEqual(["STRAIGHT"], data["command_labels"])
        self.assertEqual([], data["scene_quality_labels"])

    def test_labels_motion_quality_scene(self) -> None:
        _, data = self.run_labeler(
            replay_log(
                motion_quality_line=(
                    "roana_ios_motion_quality label=pointing_down reason=pitch_down "
                    "trusts_guidance=false source=replay"
                ),
            ),
        )

        self.assertIn("pointing_down", data["scene_quality_labels"])

    def test_blocks_when_no_command_label_is_present(self) -> None:
        text = "\n".join(
            [
                "roana_ios_replay status=started video=fixture.mp4 duration_s=2.00 fps=1.00 width=720 height=1280",
                "roana_ios_motion_quality label=stable reason=motion_unavailable trusts_guidance=true source=replay",
                "roana_ios_replay status=finished frames=0",
            ],
        ) + "\n"
        status, data = self.run_labeler(text, check=False)

        self.assertEqual(2, status)
        self.assertEqual("blocked", data["status"])
        self.assertIn("corridor_command_label", data["missing"])

    def test_rejects_missing_source(self) -> None:
        result = subprocess.run(
            [sys.executable, str(SCRIPT)],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(1, result.returncode)
        self.assertEqual("failed", json.loads(result.stdout)["status"])


if __name__ == "__main__":
    unittest.main()
