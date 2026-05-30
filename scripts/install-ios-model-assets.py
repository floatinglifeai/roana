#!/usr/bin/env python3
"""Stage local Core ML resources into the Roana iOS app bundle asset folder."""

from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPO_ROOT / "ios/Roana/Roana/ModelAssets/manifest.json"
CHECKER_SCRIPT = Path(__file__).with_name("check-ios-model-assets.py")


def load_checker_module() -> Any:
    spec = importlib.util.spec_from_file_location("check_ios_model_assets_impl", CHECKER_SCRIPT)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load {CHECKER_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHECKER = load_checker_module()
asset_candidates = CHECKER.asset_candidates
load_manifest = CHECKER.load_manifest
validate_manifest = CHECKER.validate_manifest


def model_by_id_or_resource(manifest: dict[str, Any], key: str) -> dict[str, Any]:
    normalized_key = key.lower()
    for model in manifest["models"]:
        if model["id"].lower() == normalized_key or model["resourceName"].lower() == normalized_key:
            return model
    known = ", ".join(f"{model['id']} ({model['resourceName']})" for model in manifest["models"])
    raise ValueError(f"Unknown model '{key}'. Known models: {known}")


def validate_source(source: Path, model: dict[str, Any]) -> str:
    suffix = source.suffix.removeprefix(".")
    if suffix not in model["acceptedExtensions"]:
        expected = ", ".join(f".{extension}" for extension in model["acceptedExtensions"])
        raise ValueError(f"{source} must use one of: {expected}")
    if not source.exists():
        raise FileNotFoundError(source)
    if suffix in {"mlmodelc", "mlpackage"} and not source.is_dir():
        raise ValueError(f"{source} must be a directory for .{suffix} resources")
    return suffix


def destination_for(assets_dir: Path, model: dict[str, Any], extension: str) -> Path:
    return assets_dir / f"{model['resourceName']}.{extension}"


def ensure_no_conflict(assets_dir: Path, model: dict[str, Any], destination: Path, force: bool) -> None:
    for candidate in asset_candidates(assets_dir, model):
        if candidate == destination:
            continue
        if candidate.exists():
            raise FileExistsError(
                f"Conflicting model resource already exists: {candidate}. "
                "Remove it before installing another extension.",
            )

    if destination.exists() and not force:
        raise FileExistsError(f"Destination exists: {destination}. Use --force to replace it.")


def remove_existing(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def install_model(
    source: Path,
    *,
    model: dict[str, Any],
    assets_dir: Path,
    symlink: bool,
    force: bool,
) -> Path:
    extension = validate_source(source, model)
    destination = destination_for(assets_dir, model, extension)
    ensure_no_conflict(assets_dir, model, destination, force)

    assets_dir.mkdir(parents=True, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        remove_existing(destination)

    if symlink:
        destination.symlink_to(source.resolve(), target_is_directory=source.is_dir())
    else:
        shutil.copytree(source, destination, symlinks=True)
    return destination


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument(
        "--assets-dir",
        type=Path,
        default=None,
        help="Destination ModelAssets directory. Defaults to the manifest directory.",
    )
    parser.add_argument(
        "--model",
        required=True,
        help="Manifest model id or resource name, for example yolo11n or DepthAnythingV2Small.",
    )
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--symlink", action="store_true", help="Install a symlink instead of copying.")
    parser.add_argument("--force", action="store_true", help="Replace the destination if it already exists.")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    manifest = load_manifest(args.manifest)
    errors = validate_manifest(manifest)
    if errors:
        print(json.dumps({"status": "invalid", "errors": errors}, indent=2, sort_keys=True))
        return 1

    try:
        model = model_by_id_or_resource(manifest, args.model)
        destination = install_model(
            args.source,
            model=model,
            assets_dir=args.assets_dir or args.manifest.parent,
            symlink=args.symlink,
            force=args.force,
        )
    except Exception as error:
        print(
            json.dumps(
                {
                    "status": "failed",
                    "error": str(error),
                },
                indent=2,
                sort_keys=True,
            ),
        )
        return 1

    print(
        json.dumps(
            {
                "status": "installed",
                "model": model["id"],
                "resourceName": model["resourceName"],
                "destination": str(destination),
                "mode": "symlink" if args.symlink else "copy",
            },
            indent=2,
            sort_keys=True,
        ),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
