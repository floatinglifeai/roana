#!/usr/bin/env python3
"""Offline tests for scripts/compare-litert-qnn-logs.py."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


COMPARE = Path(__file__).with_name("compare-litert-qnn-logs.py")
ANALYZER = Path(__file__).with_name("analyze-litert-smoke-log.py")


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class CompareLiteRtQnnLogsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.compare_module = load_module(COMPARE, "litert_qnn_compare_test")
        self.analyzer = load_module(ANALYZER, "litert_qnn_litert_analyzer_test")

    def test_compare_reports_per_model_timing_ratios(self) -> None:
        litert_text = "\n".join(
            [
                "05-31 10:29:17.304 I/RoanaLiteRt(14599): "
                "litert_backend requested=npu model=yolo_aot npu_provider=qualcomm "
                "qualcomm_options=full available=npu,gpu,cpu",
                "05-31 10:29:17.319 W/litert  (14599): "
                "[qnn_manager.cc:226] Qnn backend library version 5.46.0 is used. "
                "The version LiteRT using is 5.41.0.",
                "05-31 10:29:17.530 I/litert  (14599): "
                "[dispatch_delegate.cc:172] Dispatch API vendor ID: Qualcomm",
                "05-31 10:29:17.531 I/litert  (14599): "
                "[context_binary_info.cc:110] Found qnn graph: qnn_partition_0",
                "05-31 10:29:17.579 I/RoanaLiteRt(14599): "
                "litert_model_smoke status=loaded model=yolo_aot "
                "asset=yolo11n-det-int8-smart_Qualcomm_SM8550.tflite "
                "backend=unproven requested=npu load_ms=785.28",
                "05-31 10:29:17.649 I/litert  (14599):     RPC (execute) time: 11560 us",
                "05-31 10:29:17.649 I/litert  (14599):     "
                "QNN accelerator (execute) time: 11200 us",
                "05-31 10:29:17.649 I/RoanaLiteRt(14599): "
                "litert_model_timing status=ok model=yolo_aot backend=npu "
                "npu_provider=qualcomm qualcomm_options=full iterations=5 "
                "avg_ms=13.60 min_ms=13.26 max_ms=14.11",
            ]
        )
        qnn_text = (
            "05-31 10:35:38.781 I/RoanaV0a(19999): "
            "qnn_model_timing status=ok model=yolo variant=explicit_paths "
            "iterations=5 avg_ms=3.74 min_ms=2.80 max_ms=6.93\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            litert_path = Path(temp_dir) / "litert.log"
            qnn_path = Path(temp_dir) / "qnn.log"
            litert_path.write_text(litert_text, encoding="utf-8")
            qnn_path.write_text(qnn_text, encoding="utf-8")

            result = self.compare_module.compare(
                self.analyzer.analyze(litert_path),
                self.compare_module.analyze_qnn(qnn_path),
            )

        self.assertEqual(
            {
                "production_model": "yolo",
                "litert_avg_ms": 13.6,
                "qnn_avg_ms": 3.74,
                "litert_over_qnn": 3.64,
            },
            result["timing_comparison"]["yolo_aot"],
        )


if __name__ == "__main__":
    unittest.main()
