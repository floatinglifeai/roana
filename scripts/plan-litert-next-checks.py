#!/usr/bin/env python3
"""Suggest next LiteRT validation checks from classified smoke evidence."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


def load_analyzer(root: Path):
    analyzer_path = root / "scripts" / "analyze-litert-smoke-log.py"
    spec = importlib.util.spec_from_file_location("litert_log_analyzer", analyzer_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load analyzer: {analyzer_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def plan_for(result: dict[str, object]) -> dict[str, object]:
    evidence = result["evidence"]
    assert isinstance(evidence, dict)
    status = str(result["status"])

    if status in ("npu_log_evidence_present", "npu_runtime_execution_evidence_present"):
        decision = "LiteRT NPU evidence exists; compare Roana YOLO/Depth timings against production QNN."
        checks = [
            "Run MODEL=all LITERT_ACCELERATOR=npu with 5+ timing iterations.",
            "Compare against scripts/verify-qnn-smoke-device.sh timing artifacts.",
            "Only then consider a guarded LiteRT integration spike.",
        ]
    elif status == "aot_accelerator_execute_evidence_present":
        decision = "AOT reached Qualcomm accelerator execution for the positive-control model."
        checks = [
            "Record this as a positive LiteRT AOT EfficientDet control on SM8550.",
            "Repeat MODEL=efficientdet_aot with 5+ timing iterations for a less noisy timing artifact.",
            "Generate Roana YOLO/Depth AOT artifacts before any production QNN timing comparison.",
            "Do not integrate LiteRT into production until the Roana models have their own native execution proof.",
        ]
    elif status == "aot_accelerator_execute_evidence_with_runtime_warnings":
        decision = "AOT reached Qualcomm accelerator execution, but runtime warnings keep this below production proof."
        checks = [
            "Record this as positive LiteRT AOT accelerator evidence for the timed model(s), with runtime warnings.",
            "Align the Android Qualcomm runtime/provider with the nightly SDK that produced the AOT artifact so qnn_runtime_mismatch is false.",
            "Compare timings only as validation data, not as production migration proof.",
            "Do not start production integration until the runtime mismatch warning is gone and the LiteRT path beats or matches the proven TFLite+QNN path.",
        ]
    elif status == "jit_compile_failed_cpu_fallback_observed":
        decision = "Do not tune Roana models yet; current failure is below model graph compilation."
        checks = [
            "Run an AOT/AI Pack positive-control for Qualcomm_SM8550 to bypass on-device JIT.",
            "Run an official Qualcomm sample APK/model with strict NPU-required logging.",
            "Try a newer or device-matched V73 LiteRT/QNN runtime set from Google/Qualcomm.",
            "Inspect whether SELinux/FastRPC device denials correlate with QnnDevice_create 14001.",
            "Defer Roana YOLO/Depth model export changes until a small official model reaches NPU graph evidence.",
        ]
    elif status == "aot_context_create_failed":
        decision = "AOT dispatch found a precompiled QNN graph but failed to create the QNN context."
        checks = [
            "Treat this as a LiteRT AOT context-binary/runtime compatibility failure until a run shows QnnContext_create and QnnGraph_execute from the smoke PID.",
            "Run a same-session production QNN control; if it creates QNN contexts, do not change app permissions based only on FastRPC/SELinux noise.",
            "Try a Google/Qualcomm-published AI Pack or sample APK that includes a matching compiled model and runtime provider for SM8550/V73.",
            "If available, rebuild the AOT artifact with the same LiteRT compiler/runtime release that provides the Android Qualcomm dispatch library.",
            "Do not compare timings or integrate LiteRT into production until native QNN context and graph execution evidence exists.",
        ]
    elif status == "model_asset_missing":
        decision = "The AOT smoke did not package the requested compiled model asset."
        checks = [
            "Build the smoke APK with LITERT_EXTRA_ASSET_DIR pointing at a directory containing efficientdet_lite0_detection_Qualcomm_SM8550.tflite.",
            "Add or generate a matched SM8550/V73 AOT artifact before rerunning MODEL=efficientdet_aot.",
            "Do not classify this run as a LiteRT runtime/backend result.",
        ]
    elif status == "npu_provider_registration_failed_cpu_fallback_observed":
        decision = "This run did not initialize the NPU provider; do not count Java-level NPU labels as backend proof."
        checks = [
            "Use Environment.create(BuiltinNpuAcceleratorProvider(...)) for any JIT NPU check.",
            "Require native QNN device/context/graph evidence before timing comparison.",
            "If provider-backed JIT still fails, move to AOT/AI Pack or newer runtime checks.",
        ]
    elif status == "runtime_mismatch":
        decision = "Resolve LiteRT/QNN binary version mismatch before any model conclusions."
        checks = [
            "Prepare runtime with scripts/prepare-litert-qualcomm-v73-runtime.sh.",
            "Keep LiteRT Maven version aligned with the runtime release tag.",
            "Fail the gate until qnn_runtime_mismatch is false.",
        ]
    elif status == "dispatch_init_failed":
        decision = "Fix Qualcomm dispatch packaging/loading before testing model compatibility."
        checks = [
            "Verify libLiteRtDispatch_Qualcomm.so is packaged under arm64-v8a.",
            "Verify app manifest exposes required public FastRPC native libraries.",
            "Capture full logcat and rerun the native analyzer.",
        ]
    else:
        decision = "LiteRT backend remains unproven; collect stronger native evidence."
        checks = [
            "Capture full logcat with CAPTURE_FULL_LOGCAT=1.",
            "Verify dispatch/compiler plugin libraries are packaged.",
            "Run a CPU control to separate model-load errors from NPU setup errors.",
        ]

    if evidence.get("adsprpc_device_denied"):
        checks.insert(
            0,
            "Treat FastRPC SELinux denials as correlation only; compare against passing production QNN logs before changing app permissions.",
        )

    return {
        "artifact": result["artifact"],
        "status": status,
        "decision": decision,
        "evidence_summary": {
            "dispatch_vendor_qualcomm": evidence.get("dispatch_vendor_qualcomm"),
            "compiler_plugin_success_count": evidence.get("compiler_plugin_success_count"),
            "qnn_device_create_failed_code": evidence.get("qnn_device_create_failed_code"),
            "qnn_device_create_done_count": evidence.get("qnn_device_create_done_count"),
            "qnn_graph_execute_done_count": evidence.get("qnn_graph_execute_done_count"),
            "qnn_accelerator_execute_time_count": evidence.get("qnn_accelerator_execute_time_count"),
            "aot_accelerator_execute_evidence": evidence.get("aot_accelerator_execute_evidence"),
            "qnn_runtime_mismatch": evidence.get("qnn_runtime_mismatch"),
            "xnnpack_delegate_created_count": evidence.get("xnnpack_delegate_created_count"),
            "npu_accelerator_registration_failed": evidence.get("npu_accelerator_registration_failed"),
            "missing_asset": evidence.get("missing_asset"),
            "adsprpc_device_denied": evidence.get("adsprpc_device_denied"),
        },
        "next_checks": checks,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: plan-litert-next-checks.py LOG_PATH", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parents[1]
    log_path = Path(sys.argv[1])
    if not log_path.is_absolute():
        log_path = root / log_path
    analyzer = load_analyzer(root)
    print(json.dumps(plan_for(analyzer.analyze(log_path)), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
