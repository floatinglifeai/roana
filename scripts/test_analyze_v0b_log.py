#!/usr/bin/env python3
"""Offline regression tests for scripts/analyze-v0b-log.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ANALYZER = Path(__file__).with_name("analyze-v0b-log.py")


def fake_log(
    *,
    depths: list[float],
    frame_stats_count: int,
    gap_count: int,
    fp16_htp: str,
    feedback: bool = True,
    stop_feedback: bool = False,
    safe_stop: bool = False,
    malformed_safe_stop: bool = False,
) -> str:
    lines = [f"05-29 10:00:00.000 I/RoanaV0a: qnn_capabilities htp_fp16={fp16_htp}"]
    for index in range(frame_stats_count):
        line_gap_count = gap_count if index == frame_stats_count - 1 else 0
        lines.append(
            "05-29 10:00:00.100 I/RoanaV0a: "
            f"frame_stats frames={index + 1} gap_count={line_gap_count}"
        )
    if feedback:
        lines.append(
            "05-29 10:00:00.200 I/RoanaV0a: "
            "corridor_feedback status=spoken command=STRAIGHT id=roana-corridor-1"
        )
    if stop_feedback:
        lines.append(
            "05-29 10:00:00.220 I/RoanaV0a: "
            "corridor_feedback status=spoken command=STOP id=roana-corridor-3 "
            "message=stop reason=near_obstacle"
        )
    if safe_stop:
        lines.append(
            "05-29 10:00:00.250 I/RoanaV0a: "
            "debug_safe_stop_proof enabled=true reason=low_confidence decision=STOP state=STOP"
        )
        lines.append(
            "05-29 10:00:00.260 I/RoanaV0a: "
            "corridor_feedback status=spoken id=roana-corridor-2 command=STOP "
            "message=stop reason=low_confidence"
        )
    if malformed_safe_stop:
        lines.append(
            "05-29 10:00:00.250 I/RoanaV0a: "
            "debug_safe_stop_proof enabled=true reason=path_found decision=STRAIGHT state=STRAIGHT"
        )
        lines.append(
            "05-29 10:00:00.260 I/RoanaV0a: "
            "corridor_feedback status=spoken id=roana-corridor-2 command=STRAIGHT "
            "message=go_straight reason=path_found"
        )
    for depth in depths:
        lines.append(
            "05-29 10:00:00.300 I/RoanaV0a: "
            f"corridor_live status=ok depth_ms={depth:.2f} decision=STRAIGHT state=STRAIGHT"
        )
    return "\n".join(lines) + "\n"


class AnalyzeV0bLogTest(unittest.TestCase):
    def run_analyzer(
        self,
        log_path: Path,
        *,
        soc_model: str = "SM8550",
        board_platform: str = "kalama",
        thermal_log: Path | None = None,
        thermal_minutes: int = 30,
        thermal_status_before: str = "Thermal Status: 0",
        thermal_status_after: str = "Thermal Status: 0",
        require_safe_stop: bool = False,
        require_corridor_test: bool = False,
        corridor_test_result: str = "",
        corridor_test_notes: str = "",
    ) -> dict[str, object]:
        command = [
            sys.executable,
            str(ANALYZER),
            "--log",
            str(log_path),
            "--model",
            "Test Phone",
            "--soc-model",
            soc_model,
            "--board-platform",
            board_platform,
            "--abis",
            "arm64-v8a",
            "--thermal-minutes-required",
            str(thermal_minutes),
            "--require-safe-stop-proof",
            "1" if require_safe_stop else "0",
            "--require-corridor-test",
            "1" if require_corridor_test else "0",
            "--corridor-test-result",
            corridor_test_result,
            "--corridor-test-notes",
            corridor_test_notes,
        ]
        if thermal_log:
            command.extend(
                [
                    "--thermal-log",
                    str(thermal_log),
                    "--thermal-status-before",
                    thermal_status_before,
                    "--thermal-status-after",
                    thermal_status_after,
                ]
            )
        result = subprocess.run(command, check=True, capture_output=True, text=True)
        return json.loads(result.stdout)

    def test_main_gate_passes_with_target_soc_fast_depth_and_no_gaps(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(log_path, require_safe_stop=True)
            details = data["details"]

            self.assertEqual([], data["missing"])
            self.assertTrue(details["target_soc"])
            self.assertEqual("true", details["fp16_htp"])
            self.assertEqual(90.0, details["depth_elapsed_ms"])
            self.assertEqual(11.111, details["depth_fps"])
            self.assertEqual(5, details["live_corridor_count"])
            self.assertEqual(5, details["frame_stats_count"])
            self.assertEqual(0, details["gap_count"])
            self.assertIn("command=STRAIGHT", details["normal_corridor_feedback"])
            self.assertIn("debug_safe_stop_proof enabled=true", details["safe_stop_proof"])
            self.assertIn("command=STOP", details["safe_stop_feedback"])

    def test_main_gate_reports_live_stage_timing_without_affecting_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                )
                + "\n".join(
                    [
                        "05-29 10:00:00.310 I/RoanaV0a: "
                        "corridor_live_timing depth_input_ms=30.00 depth_model_ms=50.00 "
                        "depth_grid_ms=4.00 pipeline_ms=2.00 total_ms=86.00",
                        "05-29 10:00:00.320 I/RoanaV0a: "
                        "corridor_live_timing depth_input_ms=40.00 depth_model_ms=60.00 "
                        "depth_grid_ms=6.00 pipeline_ms=4.00 total_ms=110.00",
                        "05-29 10:00:00.330 I/RoanaV0a: "
                        "yolo_timing input_ms=20.00 model_ms=3.00 decode_ms=7.00 total_ms=30.00",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            data = self.run_analyzer(log_path, require_safe_stop=True)
            details = data["details"]

            self.assertEqual([], data["missing"])
            self.assertEqual(35.0, details["depth_input_elapsed_ms"])
            self.assertEqual(55.0, details["depth_model_elapsed_ms"])
            self.assertEqual(5.0, details["depth_grid_elapsed_ms"])
            self.assertEqual(3.0, details["corridor_pipeline_elapsed_ms"])
            self.assertEqual(98.0, details["corridor_total_elapsed_ms"])
            self.assertEqual(20.0, details["yolo_input_elapsed_ms"])
            self.assertEqual(3.0, details["yolo_model_elapsed_ms"])
            self.assertEqual(7.0, details["yolo_decode_elapsed_ms"])
            self.assertEqual(30.0, details["yolo_total_elapsed_ms"])

    def test_main_gate_reports_all_machine_blockers_from_slow_fallback_log(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[14000.0],
                    frame_stats_count=1,
                    gap_count=2,
                    fp16_htp="false",
                    feedback=False,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                log_path,
                soc_model="SM8350",
                board_platform="lahaina",
                require_safe_stop=True,
            )

            self.assertEqual(
                {
                    "target_soc",
                    "fp16_htp",
                    "depth_fps>=10",
                    "corridor_live_frames>=5",
                    "frame_stats>=5",
                    "no_frame_gaps",
                    "corridor_feedback_spoken",
                    "debug_safe_stop_proof",
                    "safe_stop_feedback",
                },
                set(data["missing"]),
            )

    def test_main_gate_accepts_dimensity_9300_platform_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                log_path,
                soc_model="MT6989",
                board_platform="k6989v1_64",
                require_safe_stop=True,
            )

            self.assertTrue(data["details"]["target_soc"])
            self.assertEqual([], data["missing"])

    def test_main_gate_accepts_dimensity_9400_platform_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                log_path,
                soc_model="MT6991",
                board_platform="k6991v1_64",
                require_safe_stop=True,
            )

            self.assertTrue(data["details"]["target_soc"])
            self.assertEqual([], data["missing"])

    def test_main_gate_rejects_older_mediatek_platform_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                log_path,
                soc_model="MT6983",
                board_platform="k6983v1_64",
                require_safe_stop=True,
            )

            self.assertFalse(data["details"]["target_soc"])
            self.assertEqual(["target_soc"], data["missing"])

    def test_main_gate_requires_spoken_corridor_feedback(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    feedback=False,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(log_path)

            self.assertEqual(["corridor_feedback_spoken"], data["missing"])

    def test_main_gate_requires_safe_stop_proof_when_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(log_path, require_safe_stop=True)

            self.assertEqual(["debug_safe_stop_proof", "safe_stop_feedback"], data["missing"])

    def test_safe_stop_feedback_does_not_replace_normal_corridor_feedback(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    feedback=False,
                    safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(log_path, require_safe_stop=True)

            self.assertEqual(["corridor_feedback_spoken"], data["missing"])

    def test_stop_feedback_does_not_replace_guidance_feedback(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    feedback=False,
                    stop_feedback=True,
                    safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(log_path, require_safe_stop=True)

            self.assertEqual(["corridor_feedback_spoken"], data["missing"])

    def test_safe_stop_proof_requires_stop_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    malformed_safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(log_path, require_safe_stop=True)

            self.assertEqual(["debug_safe_stop_proof", "safe_stop_feedback"], data["missing"])

    def test_thermal_gate_passes_when_long_log_stays_fast_and_gap_free(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            main_log_path = Path(temp_dir) / "main.log"
            thermal_log_path = Path(temp_dir) / "thermal.log"
            main_log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )
            thermal_log_path.write_text(
                fake_log(
                    depths=[80.0] * 120,
                    frame_stats_count=2,
                    gap_count=0,
                    fp16_htp="true",
                    feedback=False,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                main_log_path,
                thermal_log=thermal_log_path,
                thermal_minutes=2,
                require_safe_stop=True,
            )
            details = data["details"]

            self.assertEqual([], data["missing"])
            self.assertEqual([], data["thermal_missing"])
            self.assertTrue(details["thermal_gate_run"])
            self.assertEqual(120, details["thermal_live_corridor_count"])
            self.assertEqual(2, details["thermal_frame_stats_count"])
            self.assertEqual(80.0, details["thermal_depth_elapsed_ms"])
            self.assertEqual(80.0, details["thermal_tail_depth_elapsed_ms"])
            self.assertEqual(0, details["thermal_status_before_level"])
            self.assertEqual("none", details["thermal_status_before_label"])
            self.assertFalse(details["thermal_status_before_severe_or_worse"])
            self.assertEqual(0, details["thermal_status_after_level"])
            self.assertEqual("none", details["thermal_status_after_label"])
            self.assertFalse(details["thermal_status_after_severe_or_worse"])

    def test_thermal_gate_rejects_severe_numeric_status_before_run(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            main_log_path = Path(temp_dir) / "main.log"
            thermal_log_path = Path(temp_dir) / "thermal.log"
            main_log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )
            thermal_log_path.write_text(
                fake_log(
                    depths=[80.0] * 120,
                    frame_stats_count=2,
                    gap_count=0,
                    fp16_htp="true",
                    feedback=False,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                main_log_path,
                thermal_log=thermal_log_path,
                thermal_minutes=2,
                thermal_status_before="Thermal Status: 3",
                require_safe_stop=True,
            )
            details = data["details"]

            self.assertEqual(["thermal_status_before_not_severe"], data["thermal_missing"])
            self.assertEqual(3, details["thermal_status_before_level"])
            self.assertEqual("severe", details["thermal_status_before_label"])
            self.assertTrue(details["thermal_status_before_severe_or_worse"])

    def test_thermal_gate_rejects_critical_text_status_after_run(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            main_log_path = Path(temp_dir) / "main.log"
            thermal_log_path = Path(temp_dir) / "thermal.log"
            main_log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )
            thermal_log_path.write_text(
                fake_log(
                    depths=[80.0] * 120,
                    frame_stats_count=2,
                    gap_count=0,
                    fp16_htp="true",
                    feedback=False,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                main_log_path,
                thermal_log=thermal_log_path,
                thermal_minutes=2,
                thermal_status_after="mStatus=THERMAL_STATUS_CRITICAL",
                require_safe_stop=True,
            )
            details = data["details"]

            self.assertEqual(["thermal_status_after_not_severe"], data["thermal_missing"])
            self.assertEqual(4, details["thermal_status_after_level"])
            self.assertEqual("critical", details["thermal_status_after_label"])
            self.assertTrue(details["thermal_status_after_severe_or_worse"])

    def test_corridor_test_gate_requires_passed_result_when_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                log_path,
                require_safe_stop=True,
                require_corridor_test=True,
                corridor_test_result="",
            )

            self.assertEqual(["corridor_test_passed"], data["missing"])
            self.assertTrue(data["details"]["corridor_test_required"])

    def test_corridor_test_gate_records_passed_notes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "main.log"
            log_path.write_text(
                fake_log(
                    depths=[80.0, 90.0, 85.0, 95.0, 100.0],
                    frame_stats_count=5,
                    gap_count=0,
                    fp16_htp="true",
                    safe_stop=True,
                ),
                encoding="utf-8",
            )

            data = self.run_analyzer(
                log_path,
                require_safe_stop=True,
                require_corridor_test=True,
                corridor_test_result="passed",
                corridor_test_notes="known corridor, spotter present, no intervention",
            )

            self.assertEqual([], data["missing"])
            self.assertEqual("passed", data["details"]["corridor_test_result"])
            self.assertEqual(
                "known corridor, spotter present, no intervention",
                data["details"]["corridor_test_notes"],
            )


if __name__ == "__main__":
    unittest.main()
