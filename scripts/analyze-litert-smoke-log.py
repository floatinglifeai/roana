#!/usr/bin/env python3
"""Classify LiteRT smoke logs from native Qualcomm/LiteRT evidence."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


LOGCAT_PID_RE = re.compile(r"\(\s*(\d+)\):")
SMOKE_TAG_RE = re.compile(r"RoanaLiteRt\(\s*(\d+)\)")


def line_pid(line: str) -> int | None:
    match = LOGCAT_PID_RE.search(line)
    return int(match.group(1)) if match else None


def extract_smoke_pids(lines: list[str]) -> set[int]:
    pids: set[int] = set()
    for line in lines:
        match = SMOKE_TAG_RE.search(line)
        if match:
            pids.add(int(match.group(1)))
    return pids


def filter_to_pids(lines: list[str], pids: set[int]) -> list[str]:
    if not pids:
        return lines
    return [line for line in lines if line_pid(line) in pids]


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


def model_timings(lines: list[str]) -> dict[str, dict[str, object]]:
    regex = re.compile(
        r"litert_model_timing status=ok model=(\S+) "
        r"backend=(\S+) npu_provider=(\S+) qualcomm_options=(\S+) "
        r"iterations=([0-9]+) avg_ms=([0-9.]+)"
        r"(?: min_ms=([0-9.]+) max_ms=([0-9.]+))?"
    )
    timings: dict[str, dict[str, object]] = {}
    for line in lines:
        match = regex.search(line)
        if not match:
            continue
        model, backend, npu_provider, qualcomm_options, iterations, avg, min_ms, max_ms = (
            match.groups()
        )
        avg_ms = float(avg)
        timings[model] = {
            "backend": backend,
            "npu_provider": npu_provider,
            "qualcomm_options": qualcomm_options,
            "iterations": int(iterations),
            "avg_ms": avg_ms,
            "min_ms": float(min_ms) if min_ms is not None else avg_ms,
            "max_ms": float(max_ms) if max_ms is not None else avg_ms,
        }
    return timings


def analyze(path: Path) -> dict[str, object]:
    lines = path.read_text(errors="replace").splitlines()
    smoke_pids = extract_smoke_pids(lines)
    smoke_lines = filter_to_pids(lines, smoke_pids)
    native_lines = smoke_lines

    device_create_code = first_match(native_lines, r"failed to call device create, ([0-9]+)")
    context_create_code = first_match(native_lines, r"Failed to create QNN context: ([0-9]+)")
    plugin_success = first_match(native_lines, r"([0-9]+) compiler plugins were applied successfully")
    plugin_success_count = int(plugin_success) if plugin_success is not None else None
    missing_asset = first_match(smoke_lines, r"FileNotFoundException:([^ ]+\.tflite)")

    qnn_rpc_execute_time_count = count(native_lines, r"RPC \(execute\) time")
    qnn_accelerator_execute_time_count = count(
        native_lines, r"QNN accelerator \(execute\) time"
    )
    qnn_accelerator_execute_cycles_count = count(
        native_lines, r"Accelerator \(execute\) time \(cycles\)"
    )

    evidence = {
        "smoke_pids": sorted(smoke_pids),
        "native_evidence_pid_filter": bool(smoke_pids),
        "requested_npu": count(smoke_lines, r"litert_backend requested=npu ") > 0,
        "missing_asset": missing_asset,
        "model_asset_missing": missing_asset is not None,
        "native_layout_logged": count(smoke_lines, r"litert_native_layout ") > 0,
        "qualcomm_preload_loaded_count": count(smoke_lines, r"litert_qualcomm_preload status=loaded"),
        "qualcomm_preload_failed_count": count(smoke_lines, r"litert_qualcomm_preload status=failed"),
        "qualcomm_options_debug": count(smoke_lines, r"litert_qualcomm_options .*log_level=debug") > 0,
        "qualcomm_options_mode": first_match(smoke_lines, r"litert_qualcomm_options mode=([a-z]+)"),
        "npu_provider": first_match(smoke_lines, r"litert_npu_provider selected=([a-z]+)"),
        "model_loaded": count(smoke_lines, r"litert_model_smoke status=loaded ") > 0,
        "model_timing": count(smoke_lines, r"litert_model_timing status=ok ") > 0,
        "model_timings": model_timings(smoke_lines),
        "xnnpack_delegate_created_count": count(
            native_lines, r"Created TensorFlow Lite XNNPACK delegate for CPU\."
        ),
        "metadata_marked_non_executing": count(smoke_lines, r"litert_metadata_backend .*executes_model=false") > 0,
        "npu_accelerator_registration_failed": count(
            native_lines, r"NPU accelerator could not be loaded and registered"
        ) > 0,
        "compiler_plugin_attempted": count(native_lines, r"Attempting to load plugin .*libLiteRtCompilerPlugin_Qualcomm\.so") > 0,
        "compiler_plugin_success_count": plugin_success_count,
        "compiler_plugin_failed": count(native_lines, r"Plugin errs: Qualcomm compiler plugin") > 0,
        "dispatch_vendor_qualcomm": count(native_lines, r"Dispatch API vendor ID: Qualcomm") > 0,
        "dispatch_build_id": first_match(native_lines, r"Dispatch API build ID: (.*)$"),
        "dispatch_init_failed": count(native_lines, r"Failed to initialize Dispatch API") > 0,
        "qnn_runtime_mismatch": count(
            native_lines,
            r"Qnn .*mismatched|Qnn .*library version .*version LiteRT using",
        ) > 0,
        "qnn_backend_create_done_count": count(native_lines, r"QnnBackend_create done successfully"),
        "qnn_device_create_started_count": count(native_lines, r"QnnDevice_create started"),
        "qnn_device_create_done_count": count(native_lines, r"QnnDevice_create done\. device = .* status 0x0"),
        "qnn_device_create_failed_code": device_create_code,
        "qnn_context_create_done_count": count(native_lines, r"QnnContext_create done successfully"),
        "qnn_context_create_failed_code": context_create_code,
        "qnn_prepare_loaded": count(native_lines, r"First connection to QNN HTP Prepare library established|PrepareLibLoader Loading libQnnHtpPrepare\.so") > 0,
        "qnn_validate_op_success_count": count(native_lines, r"QnnBackend_validateOpConfig done successfully"),
        "qnn_graph_execute_done_count": count(native_lines, r"QnnGraph_execute done\. status 0x0|Graph .* execution finished with result 0"),
        "qnn_execute_time_count": count(native_lines, r"QNN \(execute\) time"),
        "qnn_rpc_execute_time_count": qnn_rpc_execute_time_count,
        "qnn_accelerator_execute_time_count": qnn_accelerator_execute_time_count,
        "qnn_accelerator_execute_cycles_count": qnn_accelerator_execute_cycles_count,
        "qnn_skel_opened": count(native_lines, r"Successfully opened .*libQnnHtpV[0-9]+Skel\.so|remote_handle64_open: Successfully opened handle .*libQnnHtpV[0-9]+Skel\.so") > 0,
        "qnn_stub_absolute_opened": count(native_lines, r"Attempting to open dynamically linked so: .*libQnnHtpV[0-9]+Stub\.so using absolute filename") > 0,
        "fastrpc_user_pd_created": count(native_lines, r"Created user PD on domain 3") > 0,
        "fastrpc_remote_invoke_failed_count": count(native_lines, r"remote_handle64_invoke failed"),
        "adsprpc_device_denied": count(native_lines, r"avc:.*denied.*adsprpc|/dev/adsprpc-smd") > 0,
        "qnn_graph_found": count(native_lines, r"Found qnn graph") > 0,
    }

    xnnpack_created = evidence["xnnpack_delegate_created_count"] > 0
    aot_accelerator_execute_evidence = (
        evidence["requested_npu"]
        and evidence["dispatch_vendor_qualcomm"]
        and evidence["qnn_graph_found"]
        and evidence["model_loaded"]
        and evidence["model_timing"]
        and evidence["qnn_accelerator_execute_time_count"] > 0
        and (
            evidence["qnn_rpc_execute_time_count"] > 0
            or evidence["qnn_accelerator_execute_cycles_count"] > 0
        )
    )
    evidence["aot_accelerator_execute_evidence"] = aot_accelerator_execute_evidence

    if evidence["model_asset_missing"]:
        status = "model_asset_missing"
        decision = (
            "The requested LiteRT smoke model asset was not packaged in the APK; "
            "this is not NPU backend evidence."
        )
    elif evidence["qnn_device_create_done_count"] and evidence["qnn_graph_execute_done_count"]:
        status = "npu_runtime_execution_evidence_present"
        decision = (
            "Native QNN logs show device/context creation plus graph execution; "
            "this is strong NPU execution evidence."
        )
    elif aot_accelerator_execute_evidence and evidence["qnn_runtime_mismatch"]:
        status = "aot_accelerator_execute_evidence_with_runtime_warnings"
        decision = (
            "LiteRT AOT dispatch found a QNN graph and emitted QNN accelerator "
            "execute profiling for the timed smoke model, but QNN runtime version "
            "mismatch warnings remain; treat this as a positive AOT control, not "
            "production migration proof."
        )
    elif aot_accelerator_execute_evidence:
        status = "aot_accelerator_execute_evidence_present"
        decision = (
            "LiteRT AOT dispatch found a QNN graph and emitted QNN accelerator "
            "execute profiling for the timed smoke model."
        )
    elif evidence["qnn_runtime_mismatch"]:
        status = "runtime_mismatch"
        decision = "LiteRT/QNN libraries are version-mismatched; do not treat this as NPU execution."
    elif evidence["dispatch_init_failed"]:
        status = "dispatch_init_failed"
        decision = "Qualcomm dispatch library loaded but Dispatch API did not initialize."
    elif evidence["qnn_graph_found"] and context_create_code:
        status = "aot_context_create_failed"
        decision = (
            "LiteRT AOT dispatch initialized and found a QNN graph, but failed "
            f"to create the QNN context ({context_create_code}); no graph execution proof exists."
        )
    elif evidence["npu_accelerator_registration_failed"] and xnnpack_created:
        status = "npu_provider_registration_failed_cpu_fallback_observed"
        decision = (
            "LiteRT could not register an NPU accelerator and then created the "
            "XNNPACK CPU delegate; Java-level NPU selection is a fallback false positive."
        )
    elif evidence["compiler_plugin_failed"] and device_create_code and xnnpack_created:
        status = "jit_compile_failed_cpu_fallback_observed"
        decision = (
            "Qualcomm dispatch initialized, but JIT compiler setup failed at "
            f"QNN device create ({device_create_code}) and XNNPACK CPU fallback was observed."
        )
        if evidence["adsprpc_device_denied"]:
            decision += " SELinux/FastRPC device access denials were also present."
    elif evidence["compiler_plugin_failed"] and device_create_code:
        status = "jit_compile_failed_device_create"
        decision = (
            "Qualcomm runtime dispatch initialized, but JIT compiler setup failed at "
            f"QNN device create ({device_create_code}); model backend remains unproven."
        )
    elif (
        evidence["dispatch_vendor_qualcomm"]
        and evidence["model_loaded"]
        and evidence["model_timing"]
        and (plugin_success_count or evidence["qnn_graph_found"])
        and not evidence["compiler_plugin_failed"]
    ):
        status = "npu_log_evidence_present"
        decision = "Native logs show Qualcomm dispatch plus compiled graph evidence for the timed model."
    elif evidence["dispatch_vendor_qualcomm"]:
        status = "dispatch_initialized_backend_unproven"
        decision = "Qualcomm dispatch initialized, but logs do not prove the timed model executed on NPU."
    else:
        status = "backend_unproven"
        decision = "No native Qualcomm dispatch proof was found in the LiteRT smoke log."

    return {
        "status": status,
        "artifact": str(path),
        "decision": decision,
        "evidence": evidence,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: analyze-litert-smoke-log.py LOG_PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"error: missing log file: {path}", file=sys.stderr)
        return 2
    print(json.dumps(analyze(path), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
