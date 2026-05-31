#!/usr/bin/env python3
"""Compare LiteRT Qualcomm smoke evidence with the passing TFLite QNN gate."""

from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path


def count(lines: list[str], pattern: str) -> int:
    regex = re.compile(pattern)
    return sum(1 for line in lines if regex.search(line))


def first_match(lines: list[str], pattern: str) -> str | None:
    regex = re.compile(pattern)
    for line in lines:
        match = regex.search(line)
        if match:
            return match.group(1) if match.groups() else line.strip()
    return None


def qnn_model_timings(lines: list[str]) -> dict[str, dict[str, object]]:
    regex = re.compile(
        r"qnn_model_timing status=ok model=(\S+) variant=(\S+) "
        r"iterations=([0-9]+) avg_ms=([0-9.]+) min_ms=([0-9.]+) max_ms=([0-9.]+)"
    )
    timings: dict[str, dict[str, object]] = {}
    for line in lines:
        match = regex.search(line)
        if not match:
            continue
        model, variant, iterations, avg, min_ms, max_ms = match.groups()
        timings[model] = {
            "variant": variant,
            "iterations": int(iterations),
            "avg_ms": float(avg),
            "min_ms": float(min_ms),
            "max_ms": float(max_ms),
        }
    return timings


def load_litert_analyzer(root: Path):
    analyzer_path = root / "scripts" / "analyze-litert-smoke-log.py"
    spec = importlib.util.spec_from_file_location("litert_log_analyzer", analyzer_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load analyzer: {analyzer_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def analyze_qnn(path: Path) -> dict[str, object]:
    lines = path.read_text(errors="replace").splitlines()
    evidence = {
        "qnn_options_logged": count(lines, r"qnn_options ") > 0,
        "qnn_options": first_match(lines, r"(qnn_options .*)$"),
        "qnn_probe_logged": count(lines, r"qnn_probe ") > 0,
        "qnn_capabilities_logged": count(lines, r"qnn_capabilities ") > 0,
        "qnn_model_loaded_count": count(lines, r"qnn_model_smoke status=loaded"),
        "qnn_model_timing_count": count(lines, r"qnn_model_timing status=ok"),
        "qnn_model_timings": qnn_model_timings(lines),
        "xnnpack_delegate_created_count": count(
            lines, r"Created TensorFlow Lite XNNPACK delegate for CPU\."
        ),
        "qnn_backend_create_done_count": count(lines, r"QnnBackend_create done successfully"),
        "qnn_device_create_started_count": count(lines, r"QnnDevice_create started"),
        "qnn_device_create_done_count": count(lines, r"QnnDevice_create done\. device = .* status 0x0"),
        "qnn_context_create_done_count": count(lines, r"QnnContext_create done successfully"),
        "qnn_prepare_loaded": count(lines, r"First connection to QNN HTP Prepare library established|PrepareLibLoader Loading libQnnHtpPrepare\.so") > 0,
        "qnn_validate_op_success_count": count(lines, r"QnnBackend_validateOpConfig done successfully"),
        "qnn_graph_execute_done_count": count(lines, r"QnnGraph_execute done\. status 0x0|Graph .* execution finished with result 0"),
        "qnn_execute_time_count": count(lines, r"QNN \(execute\) time"),
        "qnn_device_create_failed_count": count(lines, r"failed to call device create"),
        "qnn_skel_opened": count(lines, r"Successfully opened .*libQnnHtpV[0-9]+Skel\.so") > 0,
        "qnn_stub_absolute_opened": count(lines, r"Attempting to open dynamically linked so: .*libQnnHtpV[0-9]+Stub\.so using absolute filename") > 0,
        "fastrpc_user_pd_created": count(lines, r"Created user PD on domain 3") > 0,
        "fastrpc_remote_invoke_failed_count": count(lines, r"remote_handle64_invoke failed"),
        "adsprpc_device_denied": count(lines, r"avc:.*denied.*adsprpc|/dev/adsprpc-smd") > 0,
    }
    if evidence["qnn_device_create_done_count"] and evidence["qnn_graph_execute_done_count"]:
        status = "qnn_npu_execution_evidence_present"
        decision = "Production TFLite QNN logs show device/context creation and graph execution."
    elif evidence["qnn_device_create_done_count"]:
        status = "qnn_device_created_graph_unproven"
        decision = "Production TFLite QNN logs show device creation but no graph execution evidence."
    else:
        status = "qnn_backend_unproven"
        decision = "Production TFLite QNN log does not prove QNN execution."
    return {
        "status": status,
        "artifact": str(path),
        "decision": decision,
        "evidence": evidence,
    }


def compare(litert: dict[str, object], qnn: dict[str, object]) -> dict[str, object]:
    litert_evidence = litert["evidence"]
    qnn_evidence = qnn["evidence"]
    assert isinstance(litert_evidence, dict)
    assert isinstance(qnn_evidence, dict)

    observations = []
    if litert_evidence.get("dispatch_vendor_qualcomm"):
        observations.append("LiteRT reaches Qualcomm dispatch.")
    if litert_evidence.get("npu_accelerator_registration_failed"):
        observations.append("LiteRT did not register an NPU accelerator and created a CPU fallback delegate.")
    if litert_evidence.get("qnn_skel_opened"):
        observations.append("LiteRT reaches CDSP user-PD and opens the V73 HTP skeleton.")
    if litert_evidence.get("qnn_device_create_failed_code"):
        observations.append(
            "LiteRT fails before graph compilation at QnnDevice_create "
            f"({litert_evidence['qnn_device_create_failed_code']})."
        )
    if litert_evidence.get("qnn_context_create_failed_code"):
        observations.append(
            "LiteRT AOT found a QNN graph but failed at QnnContext_create "
            f"({litert_evidence['qnn_context_create_failed_code']})."
        )
    if litert_evidence.get("aot_accelerator_execute_evidence"):
        observations.append("LiteRT AOT emitted smoke-PID QNN accelerator execute profiling.")
    if litert_evidence.get("qnn_runtime_mismatch"):
        observations.append("LiteRT still reports QNN runtime version mismatch warnings.")
    if qnn_evidence.get("qnn_device_create_done_count"):
        observations.append("Production QNN creates the QNN device on the same phone.")
    if qnn_evidence.get("qnn_graph_execute_done_count"):
        observations.append("Production QNN executes QNN graphs on the same phone.")
    if litert_evidence.get("adsprpc_device_denied") and qnn_evidence.get("adsprpc_device_denied"):
        observations.append("FastRPC/SELinux denials are present in both logs, so they are not sufficient as a root cause.")
    elif litert_evidence.get("adsprpc_device_denied"):
        observations.append("FastRPC/SELinux denials appear in the LiteRT log; correlate with a same-run QNN control before permission changes.")

    if (
        litert_evidence.get("qnn_device_create_failed_code")
        and qnn_evidence.get("qnn_device_create_done_count")
    ):
        decision = (
            "Current evidence points to LiteRT Qualcomm JIT device setup/runtime "
            "configuration, not a global device or production QNN transport failure."
        )
    elif (
        litert_evidence.get("qnn_context_create_failed_code")
        and qnn_evidence.get("qnn_context_create_done_count")
    ):
        decision = (
            "Current evidence points to LiteRT AOT context-binary/runtime "
            "compatibility, not a global device or production QNN context failure."
        )
    elif litert["status"] == "npu_runtime_execution_evidence_present":
        decision = "LiteRT now has native NPU execution evidence; move to timing comparison."
    elif litert["status"] == "aot_accelerator_execute_evidence_with_runtime_warnings":
        decision = (
            "LiteRT AOT has accelerator execution evidence, but runtime mismatch "
            "warnings keep it below production migration proof."
        )
    elif litert["status"] == "aot_accelerator_execute_evidence_present":
        decision = "LiteRT AOT now has native accelerator execution evidence; repeat with Roana models before migration."
    else:
        decision = "LiteRT remains unproven; collect a stricter official sample or AOT control."

    litert_timings = litert_evidence.get("model_timings")
    qnn_timings = qnn_evidence.get("qnn_model_timings")
    if not isinstance(litert_timings, dict):
        litert_timings = {}
    if not isinstance(qnn_timings, dict):
        qnn_timings = {}

    timing_comparison: dict[str, dict[str, object]] = {}
    for litert_model, production_model in (
        ("yolo_aot", "yolo"),
        ("depth_aot", "depth"),
        ("yolo", "yolo"),
        ("depth", "depth"),
    ):
        litert_timing = litert_timings.get(litert_model)
        qnn_timing = qnn_timings.get(production_model)
        if not isinstance(litert_timing, dict) or not isinstance(qnn_timing, dict):
            continue
        litert_avg = litert_timing.get("avg_ms")
        qnn_avg = qnn_timing.get("avg_ms")
        if not isinstance(litert_avg, (int, float)) or not isinstance(qnn_avg, (int, float)):
            continue
        timing_comparison[litert_model] = {
            "production_model": production_model,
            "litert_avg_ms": litert_avg,
            "qnn_avg_ms": qnn_avg,
            "litert_over_qnn": round(litert_avg / qnn_avg, 2) if qnn_avg else None,
        }

    return {
        "decision": decision,
        "observations": observations,
        "litert": litert,
        "qnn": qnn,
        "timing_comparison": timing_comparison,
        "deltas": {
            "device_create": {
                "litert_failed_code": litert_evidence.get("qnn_device_create_failed_code"),
                "litert_done_count": litert_evidence.get("qnn_device_create_done_count"),
                "qnn_done_count": qnn_evidence.get("qnn_device_create_done_count"),
            },
            "context_create": {
                "litert_failed_code": litert_evidence.get("qnn_context_create_failed_code"),
                "litert_done_count": litert_evidence.get("qnn_context_create_done_count"),
                "qnn_done_count": qnn_evidence.get("qnn_context_create_done_count"),
            },
            "graph_execution": {
                "litert_done_count": litert_evidence.get("qnn_graph_execute_done_count"),
                "qnn_done_count": qnn_evidence.get("qnn_graph_execute_done_count"),
            },
            "prepare_library": {
                "litert_loaded": litert_evidence.get("qnn_prepare_loaded"),
                "qnn_loaded": qnn_evidence.get("qnn_prepare_loaded"),
            },
            "fallback": {
                "litert_xnnpack_count": litert_evidence.get("xnnpack_delegate_created_count"),
                "qnn_xnnpack_count": qnn_evidence.get("xnnpack_delegate_created_count"),
            },
        },
    }


def resolve_path(root: Path, arg: str) -> Path:
    path = Path(arg)
    if not path.is_absolute():
        path = root / path
    return path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: compare-litert-qnn-logs.py LITERT_LOG QNN_LOG", file=sys.stderr)
        return 2
    root = Path(__file__).resolve().parents[1]
    litert_path = resolve_path(root, sys.argv[1])
    qnn_path = resolve_path(root, sys.argv[2])
    if not litert_path.is_file():
        print(f"error: missing LiteRT log: {litert_path}", file=sys.stderr)
        return 2
    if not qnn_path.is_file():
        print(f"error: missing QNN log: {qnn_path}", file=sys.stderr)
        return 2

    litert_analyzer = load_litert_analyzer(root)
    result = compare(litert_analyzer.analyze(litert_path), analyze_qnn(qnn_path))
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
