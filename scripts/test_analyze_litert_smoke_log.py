#!/usr/bin/env python3
"""Offline tests for scripts/analyze-litert-smoke-log.py."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ANALYZER = Path(__file__).with_name("analyze-litert-smoke-log.py")
PLANNER = Path(__file__).with_name("plan-litert-next-checks.py")


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class AnalyzeLiteRtSmokeLogTest(unittest.TestCase):
    def setUp(self) -> None:
        self.analyzer = load_module(ANALYZER, "litert_log_analyzer_test")
        self.planner = load_module(PLANNER, "litert_next_checks_test")

    def analyze_text(self, text: str) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "litert.log"
            log_path.write_text(text, encoding="utf-8")
            return self.analyzer.analyze(log_path)

    def test_missing_aot_asset_is_not_backend_evidence(self) -> None:
        result = self.analyze_text(
            "\n".join(
                [
                    "05-31 02:06:53.321 I/RoanaLiteRt(23910): "
                    "litert_model_smoke_matrix accelerator=npu npu_provider=qualcomm "
                    "qualcomm_options=full efficientdet_aot=true timing_iterations=1",
                    "05-31 02:06:53.323 E/RoanaLiteRt(23910): "
                    "litert_runtime status=unproven model=efficientdet_aot "
                    "reason=backend_unproven:FileNotFoundException:"
                    "efficientdet_lite0_detection_Qualcomm_SM8550.tflite",
                    "05-31 02:06:53.324 E/RoanaLiteRt(23910): "
                    "litert_model_smoke status=failed model=efficientdet_aot "
                    "asset=efficientdet_lite0_detection_Qualcomm_SM8550.tflite "
                    "backend=unproven reason=backend_unproven:FileNotFoundException:"
                    "efficientdet_lite0_detection_Qualcomm_SM8550.tflite",
                ]
            )
            + "\n"
        )

        self.assertEqual("model_asset_missing", result["status"])
        evidence = result["evidence"]
        self.assertEqual(
            "efficientdet_lite0_detection_Qualcomm_SM8550.tflite",
            evidence["missing_asset"],
        )
        self.assertTrue(evidence["model_asset_missing"])
        self.assertFalse(evidence["dispatch_vendor_qualcomm"])

    def test_planner_requests_packaged_aot_asset_for_missing_asset(self) -> None:
        result = self.analyze_text(
            "05-31 02:06:53.323 E/RoanaLiteRt(23910): "
            "reason=backend_unproven:FileNotFoundException:"
            "efficientdet_lite0_detection_Qualcomm_SM8550.tflite\n"
        )
        plan = self.planner.plan_for(result)

        self.assertEqual("model_asset_missing", plan["status"])
        self.assertIn("did not package", plan["decision"])
        self.assertIn("LITERT_EXTRA_ASSET_DIR", plan["next_checks"][0])

    def test_aot_execute_profiling_with_runtime_mismatch_is_not_plain_mismatch(self) -> None:
        result = self.analyze_text(
            "\n".join(
                [
                    "05-31 09:26:03.780 I/RoanaLiteRt(30385): "
                    "litert_backend requested=npu model=efficientdet_aot "
                    "npu_provider=qualcomm qualcomm_options=full available=npu,gpu,cpu",
                    "05-31 09:26:03.817 W/litert  (30385): "
                    "[qnn_manager.cc:278] Qnn System library version 1.10.0 is used. "
                    "The version LiteRT using is 1.6.0.",
                    "05-31 09:26:04.033 I/litert  (30385): "
                    "[dispatch_delegate.cc:172] Dispatch API vendor ID: Qualcomm",
                    "05-31 09:26:04.034 I/litert  (30385): "
                    "[context_binary_info.cc:110] Found qnn graph: qnn_partition_0",
                    "05-31 09:26:04.068 I/tflite  (30385): "
                    "Created TensorFlow Lite XNNPACK delegate for CPU.",
                    "05-31 09:26:04.108 I/litert  (30385):     RPC (execute) time: 16294 us",
                    "05-31 09:26:04.108 I/litert  (30385):     "
                    "QNN accelerator (execute) time: 15937 us",
                    "05-31 09:26:04.108 I/litert  (30385):     "
                    "Accelerator (execute) time (cycles): 3415149 cycles",
                    "05-31 09:26:04.120 I/RoanaLiteRt(30385): "
                    "litert_model_smoke status=loaded model=efficientdet_aot "
                    "asset=efficientdet_lite0_detection_Qualcomm_SM8550.tflite "
                    "backend=unproven requested=npu load_ms=1130.35",
                    "05-31 09:26:04.141 I/RoanaLiteRt(30385): "
                    "litert_model_timing status=ok model=efficientdet_aot backend=npu "
                    "npu_provider=qualcomm qualcomm_options=full iterations=1 avg_ms=20.63",
                ]
            )
            + "\n"
        )

        self.assertEqual(
            "aot_accelerator_execute_evidence_with_runtime_warnings",
            result["status"],
        )
        evidence = result["evidence"]
        self.assertTrue(evidence["aot_accelerator_execute_evidence"])
        self.assertTrue(evidence["qnn_runtime_mismatch"])
        self.assertEqual(1, evidence["qnn_accelerator_execute_time_count"])
        self.assertEqual(1, evidence["qnn_rpc_execute_time_count"])
        self.assertEqual(1, evidence["qnn_accelerator_execute_cycles_count"])
        self.assertEqual(1, evidence["xnnpack_delegate_created_count"])
        self.assertEqual(
            {
                "backend": "npu",
                "npu_provider": "qualcomm",
                "qualcomm_options": "full",
                "iterations": 1,
                "avg_ms": 20.63,
                "min_ms": 20.63,
                "max_ms": 20.63,
            },
            evidence["model_timings"]["efficientdet_aot"],
        )

    def test_aot_execute_evidence_must_be_in_smoke_pid(self) -> None:
        result = self.analyze_text(
            "\n".join(
                [
                    "05-31 09:26:03.780 I/RoanaLiteRt(30385): "
                    "litert_backend requested=npu model=efficientdet_aot "
                    "npu_provider=qualcomm qualcomm_options=full available=npu,gpu,cpu",
                    "05-31 09:26:03.817 W/litert  (30385): "
                    "[qnn_manager.cc:278] Qnn System library version 1.10.0 is used. "
                    "The version LiteRT using is 1.6.0.",
                    "05-31 09:26:04.033 I/litert  (30385): "
                    "[dispatch_delegate.cc:172] Dispatch API vendor ID: Qualcomm",
                    "05-31 09:26:04.034 I/litert  (30385): "
                    "[context_binary_info.cc:110] Found qnn graph: qnn_partition_0",
                    "05-31 09:26:04.108 I/litert  (1075):     "
                    "QNN accelerator (execute) time: 15937 us",
                    "05-31 09:26:04.120 I/RoanaLiteRt(30385): "
                    "litert_model_smoke status=loaded model=efficientdet_aot "
                    "asset=efficientdet_lite0_detection_Qualcomm_SM8550.tflite "
                    "backend=unproven requested=npu load_ms=1130.35",
                    "05-31 09:26:04.141 I/RoanaLiteRt(30385): "
                    "litert_model_timing status=ok model=efficientdet_aot backend=npu "
                    "npu_provider=qualcomm qualcomm_options=full iterations=1 avg_ms=20.63",
                ]
            )
            + "\n"
        )

        self.assertEqual("runtime_mismatch", result["status"])
        evidence = result["evidence"]
        self.assertFalse(evidence["aot_accelerator_execute_evidence"])
        self.assertEqual(0, evidence["qnn_accelerator_execute_time_count"])

    def test_planner_keeps_warning_aot_control_below_production_proof(self) -> None:
        result = self.analyze_text(
            "\n".join(
                [
                    "05-31 09:26:03.780 I/RoanaLiteRt(30385): "
                    "litert_backend requested=npu model=efficientdet_aot "
                    "npu_provider=qualcomm qualcomm_options=full available=npu,gpu,cpu",
                    "05-31 09:26:03.817 W/litert  (30385): "
                    "[qnn_manager.cc:278] Qnn System library version 1.10.0 is used. "
                    "The version LiteRT using is 1.6.0.",
                    "05-31 09:26:04.033 I/litert  (30385): "
                    "[dispatch_delegate.cc:172] Dispatch API vendor ID: Qualcomm",
                    "05-31 09:26:04.034 I/litert  (30385): "
                    "[context_binary_info.cc:110] Found qnn graph: qnn_partition_0",
                    "05-31 09:26:04.108 I/litert  (30385):     RPC (execute) time: 16294 us",
                    "05-31 09:26:04.108 I/litert  (30385):     "
                    "QNN accelerator (execute) time: 15937 us",
                    "05-31 09:26:04.120 I/RoanaLiteRt(30385): "
                    "litert_model_smoke status=loaded model=efficientdet_aot "
                    "asset=efficientdet_lite0_detection_Qualcomm_SM8550.tflite "
                    "backend=unproven requested=npu load_ms=1130.35",
                    "05-31 09:26:04.141 I/RoanaLiteRt(30385): "
                    "litert_model_timing status=ok model=efficientdet_aot backend=npu "
                    "npu_provider=qualcomm qualcomm_options=full iterations=1 avg_ms=20.63",
                ]
            )
            + "\n"
        )
        plan = self.planner.plan_for(result)

        self.assertEqual(
            "aot_accelerator_execute_evidence_with_runtime_warnings",
            plan["status"],
        )
        self.assertIn("runtime warnings", plan["decision"])
        self.assertTrue(plan["evidence_summary"]["aot_accelerator_execute_evidence"])
        self.assertIn("positive LiteRT AOT accelerator evidence", plan["next_checks"][0])


if __name__ == "__main__":
    unittest.main()
