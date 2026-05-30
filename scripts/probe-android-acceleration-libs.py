#!/usr/bin/env python3
"""Probe Android acceleration-library artifact availability.

The probe is intentionally metadata-only. It does not change the app runtime or
add dependencies; it answers whether the candidate Android acceleration stacks
are currently resolvable from their official Maven repositories.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_ARTIFACTS = (
    {
        "name": "LiteRT portable runtime",
        "group": "com.google.ai.edge.litert",
        "artifact": "litert",
        "repository": "google",
        "metadata_url": "https://dl.google.com/dl/android/maven2/com/google/ai/edge/litert/litert/maven-metadata.xml",
        "role": "recommended portable layer to spike after the passing legacy QNN delegate path is protected",
    },
    {
        "name": "ONNX Runtime Android",
        "group": "com.microsoft.onnxruntime",
        "artifact": "onnxruntime-android",
        "repository": "mavenCentral",
        "metadata_url": "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/maven-metadata.xml",
        "role": "generic ORT Android baseline for diagnostic exports",
    },
    {
        "name": "ONNX Runtime Android QNN",
        "group": "com.microsoft.onnxruntime",
        "artifact": "onnxruntime-android-qnn",
        "repository": "mavenCentral",
        "metadata_url": "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android-qnn/maven-metadata.xml",
        "role": "diagnostic QNN cross-check if the TFLite/LiteRT QNN path regresses",
    },
    {
        "name": "ExecuTorch Android",
        "group": "org.pytorch",
        "artifact": "executorch-android",
        "repository": "mavenCentral",
        "metadata_url": "https://repo1.maven.org/maven2/org/pytorch/executorch-android/maven-metadata.xml",
        "role": "deferred migration candidate; useful to track because it spans more vendor backends",
    },
)


@dataclass
class Metadata:
    latest: str
    release: str
    versions: list[str]
    last_updated: str


def fetch_text(url: str, timeout_seconds: int) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "roana-android-acceleration-probe/1.0"},
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        return response.read().decode("utf-8")


def parse_metadata(xml_text: str) -> Metadata:
    root = ET.fromstring(xml_text)
    versioning = root.find("versioning")
    if versioning is None:
        raise ValueError("metadata has no versioning element")

    latest = text_or_empty(versioning.find("latest"))
    release = text_or_empty(versioning.find("release"))
    versions = [
        version.text.strip()
        for version in versioning.findall("./versions/version")
        if version.text and version.text.strip()
    ]
    last_updated = text_or_empty(versioning.find("lastUpdated"))

    if not latest and not release and not versions:
        raise ValueError("metadata has no versions")

    return Metadata(
        latest=latest or (versions[-1] if versions else ""),
        release=release,
        versions=versions,
        last_updated=last_updated,
    )


def text_or_empty(element: ET.Element | None) -> str:
    return element.text.strip() if element is not None and element.text else ""


def probe_artifact(
    artifact: dict[str, str],
    timeout_seconds: int,
    fetcher=fetch_text,
) -> dict[str, object]:
    try:
        metadata = parse_metadata(fetcher(artifact["metadata_url"], timeout_seconds))
        status = "available" if metadata.latest else "unavailable"
        return {
            **artifact,
            "status": status,
            "latest": metadata.latest,
            "release": metadata.release,
            "last_updated": metadata.last_updated,
            "version_count": len(metadata.versions),
            "recent_versions": metadata.versions[-8:],
        }
    except (OSError, TimeoutError, ValueError, ET.ParseError, urllib.error.URLError) as error:
        return {
            **artifact,
            "status": "unavailable",
            "error": f"{error.__class__.__name__}: {error}",
        }


def decision(results: list[dict[str, object]]) -> str:
    available = {
        str(result["artifact"]): result
        for result in results
        if result.get("status") == "available"
    }
    if "litert" not in available:
        return "LiteRT metadata is unavailable; keep the existing QNN HTP delegate path and do not start a migration spike."
    if "onnxruntime-android-qnn" not in available:
        return "LiteRT is available, but ORT QNN diagnostic metadata is unavailable; use LiteRT as the only near-term alternative spike."
    if "executorch-android" not in available:
        return "LiteRT and ORT QNN are available; ExecuTorch is not currently resolvable, so keep it deferred."
    return "All tracked candidate artifacts are resolvable. Keep the passing QNN HTP delegate as the production path; next optional spike is LiteRT metadata/API exploration, with ORT QNN reserved as a diagnostic cross-check and ExecuTorch deferred."


def build_report(
    *,
    artifacts: tuple[dict[str, str], ...] = DEFAULT_ARTIFACTS,
    timeout_seconds: int = 20,
    fetcher=fetch_text,
) -> dict[str, object]:
    results = [
        probe_artifact(artifact, timeout_seconds=timeout_seconds, fetcher=fetcher)
        for artifact in artifacts
    ]
    return {
        "status": "passed" if all(result["status"] == "available" for result in results) else "failed",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "hypothesis": "Android acceleration-library candidates are discoverable before any runtime migration work starts",
        "decision": decision(results),
        "artifacts": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout-seconds", type=int, default=20)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report = build_report(timeout_seconds=args.timeout_seconds)

    payload = json.dumps(report, indent=2, sort_keys=True)
    print(payload)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload + "\n", encoding="utf-8")

    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
