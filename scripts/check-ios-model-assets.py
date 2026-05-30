#!/usr/bin/env python3
"""Validate the Roana iOS Core ML model asset contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


REQUIRED_MODEL_FIELDS = ("id", "resourceName", "acceptedExtensions", "runtime", "source")
EXPECTED_MODEL_CONTRACTS = {
    "yolo11n": {
        "expectedInput": {"width": 640, "height": 640},
        "expectedOutputs": {"VNRecognizedObjectObservation"},
    },
    "depth-anything-v2-small": {
        "expectedInput": {"width": 518, "height": 518},
        "expectedOutputs": {"MLMultiArray"},
    },
}
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPO_ROOT / "ios/Roana/Roana/ModelAssets/manifest.json"


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if manifest.get("schema") != 1:
        errors.append("schema=1")

    models = manifest.get("models")
    if not isinstance(models, list) or not models:
        errors.append("models")
        return errors

    resource_names: set[str] = set()
    for index, model in enumerate(models):
        if not isinstance(model, dict):
            errors.append(f"models[{index}]")
            continue

        for field in REQUIRED_MODEL_FIELDS:
            if field not in model:
                errors.append(f"models[{index}].{field}")

        resource_name = model.get("resourceName")
        if isinstance(resource_name, str) and resource_name:
            if resource_name in resource_names:
                errors.append(f"duplicate resourceName={resource_name}")
            resource_names.add(resource_name)
        else:
            errors.append(f"models[{index}].resourceName")

        accepted_extensions = model.get("acceptedExtensions")
        if not isinstance(accepted_extensions, list) or not accepted_extensions:
            errors.append(f"models[{index}].acceptedExtensions")
            continue
        for extension in accepted_extensions:
            if extension not in {"mlmodelc", "mlpackage"}:
                errors.append(f"models[{index}].acceptedExtensions={extension}")

        model_id = model.get("id")
        if isinstance(model_id, str) and model_id in EXPECTED_MODEL_CONTRACTS:
            errors.extend(validate_expected_contract(index, model, EXPECTED_MODEL_CONTRACTS[model_id]))

    return errors


def validate_expected_contract(
    index: int,
    model: dict[str, Any],
    expected: dict[str, Any],
) -> list[str]:
    errors: list[str] = []

    expected_input = model.get("expectedInput")
    if expected_input != expected["expectedInput"]:
        errors.append(f"models[{index}].expectedInput={expected['expectedInput']}")

    expected_outputs = model.get("expectedOutputs")
    if not isinstance(expected_outputs, list) or set(expected_outputs) != expected["expectedOutputs"]:
        errors.append(f"models[{index}].expectedOutputs={sorted(expected['expectedOutputs'])}")

    return errors


def asset_candidates(assets_dir: Path, model: dict[str, Any]) -> list[Path]:
    resource_name = str(model["resourceName"])
    return [
        assets_dir / f"{resource_name}.{extension}"
        for extension in model["acceptedExtensions"]
    ]


def inspect_assets(manifest: dict[str, Any], assets_dir: Path) -> dict[str, Any]:
    models = []
    missing = []
    conflicts = []

    for model in manifest["models"]:
        candidates = asset_candidates(assets_dir, model)
        present = [path for path in candidates if path.exists()]
        if not present:
            missing.append(model["id"])
        if len(present) > 1:
            conflicts.append(model["id"])
        models.append(
            {
                "id": model["id"],
                "resourceName": model["resourceName"],
                "present": [str(path) for path in present],
                "expected": [str(path) for path in candidates],
            },
        )

    return {
        "missing": missing,
        "conflicts": conflicts,
        "models": models,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
    )
    parser.add_argument(
        "--assets-dir",
        type=Path,
        default=None,
        help="Directory containing local .mlpackage or .mlmodelc resources.",
    )
    parser.add_argument(
        "--require-present",
        action="store_true",
        help="Fail if any manifest model is missing locally.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    manifest = load_manifest(args.manifest)
    assets_dir = args.assets_dir or args.manifest.parent
    manifest_errors = validate_manifest(manifest)

    if manifest_errors:
        result = {
            "status": "invalid",
            "errors": manifest_errors,
            "assetsDir": str(assets_dir),
        }
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1

    inspection = inspect_assets(manifest, assets_dir)
    missing = inspection["missing"]
    conflicts = inspection["conflicts"]
    status = "ready" if not missing and not conflicts else "missing"
    if conflicts:
        status = "invalid"

    result = {
        "status": status,
        "assetsDir": str(assets_dir),
        **inspection,
    }
    print(json.dumps(result, indent=2, sort_keys=True))

    if conflicts:
        return 1
    if args.require_present and missing:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
