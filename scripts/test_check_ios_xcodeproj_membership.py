#!/usr/bin/env python3
"""Tests for the iOS Xcode project membership checker."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check-ios-xcodeproj-membership.py")


def write_project(path: Path, *, include_extra: bool = True, include_model_assets: bool = True) -> None:
    extra_build = '\t\tB3 /* Extra.swift in Sources */ = {isa = PBXBuildFile; fileRef = F3 /* Extra.swift */; };\n'
    extra_ref = '\t\tF3 /* Extra.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Extra.swift; sourceTree = "<group>"; };\n'
    model_assets = '\t\tR2 /* ModelAssets in Resources */ = {isa = PBXBuildFile; fileRef = FR2 /* ModelAssets */; };\n'
    path.write_text(
        "// !$*UTF8*$!\n"
        "{\n"
        "\tobjects = {\n"
        "/* Begin PBXBuildFile section */\n"
        "\t\tB1 /* App.swift in Sources */ = {isa = PBXBuildFile; fileRef = F1 /* App.swift */; };\n"
        "\t\tB2 /* Camera.swift in Sources */ = {isa = PBXBuildFile; fileRef = F2 /* Camera.swift */; };\n"
        f"{extra_build if include_extra else ''}"
        "\t\tR1 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = FR1 /* Assets.xcassets */; };\n"
        f"{model_assets if include_model_assets else ''}"
        "/* End PBXBuildFile section */\n"
        "/* Begin PBXFileReference section */\n"
        "\t\tF1 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = \"<group>\"; };\n"
        "\t\tF2 /* Camera.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Camera.swift; sourceTree = \"<group>\"; };\n"
        f"{extra_ref if include_extra else ''}"
        "\t\tFR1 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };\n"
        "\t\tFR2 /* ModelAssets */ = {isa = PBXFileReference; lastKnownFileType = folder; path = ModelAssets; sourceTree = \"<group>\"; };\n"
        "/* End PBXFileReference section */\n"
        "/* Begin PBXResourcesBuildPhase section */\n"
        "\t\tRES /* Resources */ = { files = (\n"
        "\t\t\tR1 /* Assets.xcassets in Resources */,\n"
        f"{'\t\t\tR2 /* ModelAssets in Resources */,\n' if include_model_assets else ''}"
        "\t\t); };\n"
        "/* End PBXResourcesBuildPhase section */\n"
        "/* Begin PBXSourcesBuildPhase section */\n"
        "\t\tSRC /* Sources */ = { files = (\n"
        "\t\t\tB1 /* App.swift in Sources */,\n"
        "\t\t\tB2 /* Camera.swift in Sources */,\n"
        f"{'\t\t\tB3 /* Extra.swift in Sources */,\n' if include_extra else ''}"
        "\t\t); };\n"
        "/* End PBXSourcesBuildPhase section */\n"
        "\t};\n"
        "}\n",
        encoding="utf-8",
    )


def write_sources(source_root: Path) -> None:
    source_root.mkdir(parents=True)
    (source_root / "App.swift").write_text("struct App {}\n", encoding="utf-8")
    (source_root / "Camera.swift").write_text("struct Camera {}\n", encoding="utf-8")
    (source_root / "Extra.swift").write_text("struct Extra {}\n", encoding="utf-8")


class CheckIosXcodeprojMembershipTest(unittest.TestCase):
    def run_checker(self, project: Path, source_root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--project",
                str(project),
                "--source-root",
                str(source_root),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_all_sources_and_resources_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source_root = root / "Roana"
            project = root / "project.pbxproj"
            write_sources(source_root)
            write_project(project)

            result = self.run_checker(project, source_root)

        details = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(details["status"], "passed")
        self.assertEqual(details["sourceCount"], 3)

    def test_missing_source_membership_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source_root = root / "Roana"
            project = root / "project.pbxproj"
            write_sources(source_root)
            write_project(project, include_extra=False)

            result = self.run_checker(project, source_root)

        details = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(details["status"], "failed")
        self.assertIn("missing_source_file_refs", details["errors"])
        self.assertIn("missing_source_membership", details["errors"])
        self.assertEqual(details["missingSourceMembership"], ["Extra.swift"])

    def test_missing_model_assets_resource_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source_root = root / "Roana"
            project = root / "project.pbxproj"
            write_sources(source_root)
            write_project(project, include_model_assets=False)

            result = self.run_checker(project, source_root)

        details = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(details["missingResources"], ["ModelAssets"])


if __name__ == "__main__":
    unittest.main()
