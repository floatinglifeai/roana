#!/usr/bin/env python3
"""Tests for the iOS physical-device log verifier."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("verify-ios-device-log.py")
spec = importlib.util.spec_from_file_location("verify_ios_device_log", SCRIPT)
assert spec is not None
verify_ios_device_log = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(verify_ios_device_log)


def fake_log(
    *,
    frame_count: int,
    include_yolo: bool = False,
    include_yolo_description: bool = False,
    include_depth: bool = False,
    include_depth_description: bool = False,
    include_corridor: bool = False,
    include_speech: bool = False,
    speech_label: str = "person",
    include_fail_safe_stop: bool = False,
    include_inference: bool = False,
    model_mode: str = "disabled",
    p95_ms: float = 34.0,
    run_seconds: float = 60.0,
    thermal_state: str = "nominal",
    include_orientation: bool = False,
    include_background_stop: bool = False,
    include_background_restart: bool = False,
    include_idle_timer: bool = False,
    inference_skipped: int = 0,
) -> str:
    lines = [
        "roana_ios_lifecycle camera_authorization state=authorized",
        "roana_ios_lifecycle camera_started",
        f"roana_ios_model_mode value={model_mode}",
    ]
    if include_orientation:
        lines.append("roana_ios_lifecycle camera_output_orientation interface=portrait angle=90 vision=right")
        lines.append("roana_ios_orientation source=preview interface=portrait angle=90 vision=right")
    if include_idle_timer:
        lines.append("roana_ios_lifecycle idle_timer_disabled value=true")
    for index in range(frame_count):
        lines.append(
            "roana_ios_frame_stats "
            "width=1280 height=720 pixel_format=420YpCbCr8BiPlanarFullRange "
            f"interval_ms=33.30 p50_ms=33.30 p95_ms={p95_ms:.2f} dropped=0 backlog=0 "
            f"thermal={thermal_state} run_s={run_seconds:.2f} frame={index}"
        )
    if include_yolo:
        if include_inference:
            lines.append("roana_ios_inference status=scheduled frame_id=1")
        lines.append(
            "roana_ios_yolo status=ready elapsed_ms=12.00 vision=right label=person "
            "score=0.91 center_x=0.50 center_y=0.80 width=0.20 height=0.30"
        )
        if include_inference:
            if inference_skipped:
                lines.append(f"roana_ios_inference status=skipped reason=busy skipped={inference_skipped}")
            lines.append(f"roana_ios_inference status=finished frame_id=1 completed=1 skipped={inference_skipped}")
    if include_yolo_description:
        lines.append(
            "roana_ios_yolo status=model_description resource=YOLO11n "
            "author=unknown version=unknown inputs=image:image_640x640 "
            "outputs=coordinates:multiarray_1x100x4_float32,confidence:multiarray_1x100x80_float32"
        )
    if include_depth:
        lines.append("roana_ios_depth status=ok elapsed_ms=31.00 vision=right grid_rows=15 grid_cols=15")
    if include_depth_description:
        lines.append(
            "roana_ios_depth status=model_description resource=DepthAnythingV2Small "
            "author=unknown version=unknown inputs=image:image_518x392 "
            "outputs=depth:image_518x392"
        )
    if include_corridor:
        lines.append(
            "roana_ios_corridor decision=STRAIGHT state=STRAIGHT "
            "reason=path_found path_cells=15 pending=none pending_count=0"
        )
        lines.append("roana_ios_audio_session status=active category=playback mode=spokenAudio options=duckOthers")
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
        if not include_speech:
            lines.append(
                "roana_ios_speech status=suppressed reason=corridor_feedback_active "
                "label=person score=91"
            )
    if include_speech:
        lines.append("roana_ios_audio_session status=active category=playback mode=spokenAudio options=duckOthers")
        lines.append(f"roana_ios_speech status=queued label={speech_label} score=91 message=Person_ahead")
    if include_fail_safe_stop:
        lines.append("roana_ios_safety event=fail_safe_stop reason=frame_loss")
        lines.append(
            "roana_ios_corridor decision=STOP state=STOP "
            "reason=frame_loss path_cells=0 pending=none pending_count=0"
        )
    if include_background_stop:
        if include_idle_timer:
            lines.append("roana_ios_lifecycle idle_timer_disabled value=false")
        lines.append("roana_ios_lifecycle camera_background_stop phase=background")
    if include_background_restart:
        lines.append("roana_ios_lifecycle camera_started")
    return "\n".join(lines) + "\n"


def fake_denied_log() -> str:
    return "\n".join(
        [
            "roana_ios_model_mode value=disabled",
            "roana_ios_lifecycle camera_authorization state=denied",
            "roana_ios_lifecycle camera_permission_denied state=denied",
        ],
    ) + "\n"


class VerifyIosDeviceLogTest(unittest.TestCase):
    def test_devicectl_json_requires_iphone(self) -> None:
        payload = {"result": {"devices": []}}

        missing = verify_ios_device_log.iphone_device_readiness_from_devicectl_json(json.dumps(payload))

        self.assertEqual(["iphone_device"], missing)

    def test_devicectl_json_rejects_unavailable_iphone(self) -> None:
        payload = {
            "result": {
                "devices": [
                    {
                        "hardwareProperties": {
                            "platform": "iOS",
                            "deviceType": "iPhone",
                        },
                        "connectionProperties": {
                            "tunnelState": "unavailable",
                        },
                        "deviceProperties": {
                            "ddiServicesAvailable": False,
                        },
                    },
                ],
            },
        }

        missing = verify_ios_device_log.iphone_device_readiness_from_devicectl_json(json.dumps(payload))

        self.assertEqual(["iphone_device_available"], missing)

    def test_devicectl_json_accepts_available_iphone_tunnel(self) -> None:
        payload = {
            "result": {
                "devices": [
                    {
                        "hardwareProperties": {
                            "platform": "iOS",
                            "deviceType": "iPhone",
                        },
                        "connectionProperties": {
                            "tunnelState": "connected",
                        },
                        "deviceProperties": {
                            "ddiServicesAvailable": False,
                        },
                    },
                ],
            },
        }

        missing = verify_ios_device_log.iphone_device_readiness_from_devicectl_json(json.dumps(payload))

        self.assertEqual([], missing)

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
            fake_log(
                frame_count=120,
                include_orientation=True,
                include_background_stop=True,
                include_background_restart=True,
                include_idle_timer=True,
            ),
            "--gate",
            "s0",
        )

        self.assertEqual(status, 0)
        self.assertEqual(details["status"], "passed")
        self.assertEqual(details["missing"], [])
        self.assertEqual(["disabled"], details["analysis"]["details"]["model_modes"])

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
        self.assertIn("yolo_speech_match", details["missing"])
        self.assertIn("audio_session_active", details["missing"])
        self.assertIn("preview_orientation", details["missing"])
        self.assertIn("capture_orientation", details["missing"])
        self.assertIn("camera_background_restart", details["missing"])
        self.assertIn("idle_timer_disabled", details["missing"])
        self.assertIn("idle_timer_enabled", details["missing"])
        self.assertIn("inference_finished", details["missing"])
        self.assertIn("yolo_vision_orientation", details["missing"])

    def test_v0a_defaults_require_speech_to_match_yolo_detection(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_speech=True,
                speech_label="chair",
                include_inference=True,
                model_mode="yolo",
            ),
            "--gate",
            "v0a",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("yolo_speech_match", details["missing"])
        self.assertEqual(["person"], details["analysis"]["details"]["yolo_detection_labels"])
        self.assertEqual(["chair"], details["analysis"]["details"]["speech_labels"])
        self.assertEqual([], details["analysis"]["details"]["matched_yolo_speech_labels"])

    def test_v0a_defaults_require_audio_session_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_speech=True,
                include_inference=True,
                model_mode="yolo",
            ).replace(
                "roana_ios_audio_session status=active category=playback mode=spokenAudio options=duckOthers\n",
                "",
            ),
            "--gate",
            "v0a",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("audio_session_active", details["missing"])

    def test_v0a_defaults_require_yolo_model_mode(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_speech=True,
                include_inference=True,
                model_mode="disabled",
            ),
            "--gate",
            "v0a",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("model_mode>=yolo", details["missing"])

    def test_s0_defaults_require_sixty_second_run(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                run_seconds=12.5,
                include_orientation=True,
                include_background_stop=True,
                include_background_restart=True,
                include_idle_timer=True,
            ),
            "--gate",
            "s0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("run_s>=60", details["missing"])

    def test_v0b_log_passes_with_model_corridor_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
            ),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 0)
        self.assertEqual(details["status"], "passed")

    def test_v0b_defaults_do_not_require_generic_yolo_speech(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
            ),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 0)
        self.assertEqual(details["status"], "passed")
        self.assertEqual(0, details["analysis"]["details"]["speech_queued_count"])
        self.assertEqual(["frame_loss"], details["analysis"]["details"]["safety_fail_safe_stop_reasons"])
        self.assertEqual(["corridor"], details["analysis"]["details"]["model_modes"])

    def test_v0b_defaults_require_model_descriptions(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_depth=True,
                include_corridor=True,
                include_speech=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
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

    def test_v0b_defaults_require_expected_model_resources(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
            )
            .replace("resource=YOLO11n", "resource=WrongYolo")
            .replace("resource=DepthAnythingV2Small", "resource=WrongDepth"),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("yolo_model_resource", details["missing"])
        self.assertIn("depth_model_resource", details["missing"])

    def test_v0b_defaults_require_model_feature_descriptions(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
            )
            .replace("inputs=image:image_640x640", "inputs=unknown")
            .replace(
                "outputs=coordinates:multiarray_1x100x4_float32,confidence:multiarray_1x100x80_float32",
                "outputs=unknown",
            )
            .replace("inputs=image:image_518x392", "inputs=unknown")
            .replace("outputs=depth:image_518x392", "outputs=unknown"),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("yolo_model_features", details["missing"])
        self.assertIn("depth_model_features", details["missing"])

    def test_v0b_defaults_require_vision_orientation_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
            ).replace(" vision=right", ""),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("yolo_vision_orientation", details["missing"])
        self.assertIn("depth_vision_orientation", details["missing"])

    def test_v0b_defaults_require_matching_vision_orientation_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
            ).replace("roana_ios_depth status=ok elapsed_ms=31.00 vision=right", "roana_ios_depth status=ok elapsed_ms=31.00 vision=left"),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("depth_vision_orientation_match", details["missing"])

    def test_v0b_defaults_require_ten_fps_cadence(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                p95_ms=125.0,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
            ),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("p95_ms<=101", details["missing"])

    def test_v0b_defaults_tolerate_recovery_inference_skips(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                p95_ms=100.01,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                inference_skipped=5,
                model_mode="corridor",
            ),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 0)
        self.assertEqual(details["status"], "passed")
        self.assertEqual(5, details["analysis"]["details"]["max_inference_skipped"])

    def test_v0b_defaults_reject_thermal_throttle(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                thermal_state="serious",
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_fail_safe_stop=True,
                include_inference=True,
                model_mode="corridor",
            ),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("thermal<=fair", details["missing"])

    def test_v0b_defaults_require_fail_safe_stop_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_background_stop=True,
                include_background_restart=True,
                include_orientation=True,
                include_idle_timer=True,
                include_yolo=True,
                include_yolo_description=True,
                include_depth=True,
                include_depth_description=True,
                include_corridor=True,
                include_inference=True,
                model_mode="corridor",
            ),
            "--gate",
            "v0b",
            "--require-model-assets",
            "0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("fail_safe_stop", details["missing"])

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
        self.assertIn("camera_background_restart", details["missing"])
        self.assertIn("idle_timer_disabled", details["missing"])
        self.assertIn("idle_timer_enabled", details["missing"])

    def test_s0_defaults_require_background_restart_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(frame_count=120, include_orientation=True, include_background_stop=True),
            "--gate",
            "s0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("camera_background_restart", details["missing"])

    def test_s0_defaults_require_idle_timer_evidence(self) -> None:
        status, details = self.run_verifier(
            fake_log(
                frame_count=120,
                include_orientation=True,
                include_background_stop=True,
                include_background_restart=True,
            ),
            "--gate",
            "s0",
        )

        self.assertEqual(status, 2)
        self.assertEqual(details["status"], "blocked")
        self.assertIn("idle_timer_disabled", details["missing"])
        self.assertIn("idle_timer_enabled", details["missing"])

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
