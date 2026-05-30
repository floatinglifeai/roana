#!/usr/bin/env python3
"""Check that the iOS Xcode project includes required app sources/resources."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT = REPO_ROOT / "ios/Roana/Roana.xcodeproj/project.pbxproj"
DEFAULT_SOURCE_ROOT = REPO_ROOT / "ios/Roana/Roana"


def production_swift_files(source_root: Path) -> list[str]:
    return sorted(
        str(path.relative_to(source_root))
        for path in source_root.rglob("*.swift")
        if path.is_file()
    )


def build_phase_names(project_text: str, phase_name: str) -> set[str]:
    pattern = re.compile(r"/\* Begin PBX" + re.escape(phase_name) + r"BuildPhase section \*/(?P<body>.*?)/\* End PBX", re.S)
    match = pattern.search(project_text)
    if match is None:
        return set()

    return set(re.findall(r"/\* ([^*/]+?) in " + re.escape(phase_name) + r" \*/", match.group("body")))


def file_reference_names(project_text: str) -> set[str]:
    return set(re.findall(r"/\* ([^*/]+?) \*/ = \{isa = PBXFileReference;", project_text))


def check_membership(
    project: Path,
    source_root: Path,
) -> dict[str, Any]:
    project_text = project.read_text(encoding="utf-8")
    source_files = production_swift_files(source_root)
    source_names = [Path(path).name for path in source_files]
    source_phase = build_phase_names(project_text, "Sources")
    resources_phase = build_phase_names(project_text, "Resources")
    file_refs = file_reference_names(project_text)

    missing_source_file_refs = sorted(name for name in source_names if name not in file_refs)
    missing_source_membership = sorted(name for name in source_names if name not in source_phase)
    missing_resources = sorted(name for name in ["Assets.xcassets", "ModelAssets"] if name not in resources_phase)
    duplicate_source_names = sorted(
        name
        for name in set(source_names)
        if source_names.count(name) > 1
    )

    errors = []
    if missing_source_file_refs:
        errors.append("missing_source_file_refs")
    if missing_source_membership:
        errors.append("missing_source_membership")
    if missing_resources:
        errors.append("missing_resources")
    if duplicate_source_names:
        errors.append("duplicate_source_names")

    return {
        "status": "passed" if not errors else "failed",
        "errors": errors,
        "project": str(project),
        "sourceRoot": str(source_root),
        "sourceCount": len(source_files),
        "missingSourceFileRefs": missing_source_file_refs,
        "missingSourceMembership": missing_source_membership,
        "missingResources": missing_resources,
        "duplicateSourceNames": duplicate_source_names,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=DEFAULT_PROJECT)
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE_ROOT)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    result = check_membership(args.project, args.source_root)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
