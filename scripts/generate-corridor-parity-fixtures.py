#!/usr/bin/env python3
"""Regenerate Android-to-iOS corridor parity fixtures with a compatible JDK."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GRADLEW = REPO_ROOT / "gradlew"
PARITY_FIXTURE = REPO_ROOT / "parity/corridor-core.json"
COMPATIBLE_JDK_MAJORS = {17, 21}


@dataclass(frozen=True)
class JdkCandidate:
    source: str
    path: Path
    status: str
    major: int | None = None
    version: str | None = None
    reason: str | None = None

    def to_json(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "source": self.source,
            "path": str(self.path),
            "status": self.status,
        }
        if self.major is not None:
            result["major"] = self.major
        if self.version is not None:
            result["version"] = self.version
        if self.reason is not None:
            result["reason"] = self.reason
        return result


def parse_java_major(version: str) -> int | None:
    match = re.search(r'(?:"|^)(\d+)(?:\.|")', version)
    if not match:
        return None
    return int(match.group(1))


def read_release_version(java_home: Path) -> str | None:
    release_file = java_home / "release"
    if not release_file.is_file():
        return None

    for line in release_file.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("JAVA_VERSION="):
            return line.split("=", 1)[1].strip().strip('"')
    return None


def run_java_version(java_home: Path) -> str | None:
    java = java_home / "bin/java"
    if not java.is_file():
        return None

    result = subprocess.run(
        [str(java), "-version"],
        check=False,
        capture_output=True,
        text=True,
    )
    output = "\n".join(part for part in [result.stdout, result.stderr] if part)
    return output.strip() or None


def inspect_jdk(source: str, path_text: str) -> JdkCandidate:
    path = Path(path_text).expanduser()
    if path.is_file():
        return JdkCandidate(
            source=source,
            path=path,
            status="invalid",
            reason="java_home_points_to_executable",
        )

    java = path / "bin/java"
    if not java.is_file():
        return JdkCandidate(
            source=source,
            path=path,
            status="invalid",
            reason="missing_bin_java",
        )

    version = read_release_version(path) or run_java_version(path)
    if version is None:
        return JdkCandidate(
            source=source,
            path=path,
            status="invalid",
            reason="unreadable_java_version",
        )

    major = parse_java_major(version)
    if major is None:
        return JdkCandidate(
            source=source,
            path=path,
            status="invalid",
            version=version,
            reason="unparseable_java_version",
        )

    if major not in COMPATIBLE_JDK_MAJORS:
        return JdkCandidate(
            source=source,
            path=path,
            status="incompatible",
            major=major,
            version=version,
            reason=f"requires_jdk_{min(COMPATIBLE_JDK_MAJORS)}_or_{max(COMPATIBLE_JDK_MAJORS)}",
        )

    return JdkCandidate(
        source=source,
        path=path,
        status="compatible",
        major=major,
        version=version,
    )


def macos_java_home(version: int) -> Path | None:
    helper = Path("/usr/libexec/java_home")
    if not helper.is_file():
        return None

    result = subprocess.run(
        [str(helper), "-v", str(version)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    path_text = result.stdout.strip()
    return Path(path_text) if path_text else None


def discover_candidates(args: argparse.Namespace) -> list[JdkCandidate]:
    raw_candidates: list[tuple[str, str]] = []

    if args.java_home:
        raw_candidates.append(("argument", str(args.java_home)))
    else:
        env_java_home = os.environ.get("JAVA_HOME")
        if env_java_home:
            raw_candidates.append(("JAVA_HOME", env_java_home))

        if not args.no_system_discovery:
            for major in [21, 17]:
                java_home = macos_java_home(major)
                if java_home is not None:
                    raw_candidates.append((f"/usr/libexec/java_home -v {major}", str(java_home)))

            for path in [
                "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
                "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home",
                "/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home",
                "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home",
            ]:
                raw_candidates.append(("known_path", path))

    candidates: list[JdkCandidate] = []
    seen: set[Path] = set()
    for source, path_text in raw_candidates:
        path = Path(path_text).expanduser()
        if path in seen:
            continue
        seen.add(path)
        candidates.append(inspect_jdk(source, path_text))

    return candidates


def build_gradle_command(gradlew: Path) -> list[str]:
    return [str(gradlew), ":app:generateCorridorParityFixtures", "--no-daemon"]


def build_ready_result(candidate: JdkCandidate, command: list[str]) -> dict[str, Any]:
    return {
        "status": "ready",
        "javaHome": str(candidate.path),
        "javaMajor": candidate.major,
        "javaVersion": candidate.version,
        "fixture": str(PARITY_FIXTURE),
        "command": command,
    }


def build_blocked_result(candidates: list[JdkCandidate]) -> dict[str, Any]:
    return {
        "status": "blocked",
        "reason": "compatible_jdk_missing",
        "requires": sorted(COMPATIBLE_JDK_MAJORS),
        "candidates": [candidate.to_json() for candidate in candidates],
        "hint": "Install or select a JDK 17 or 21 home, then rerun this script.",
    }


def print_json(result: dict[str, Any]) -> None:
    print(json.dumps(result, indent=2, sort_keys=True))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--java-home",
        type=Path,
        default=None,
        help="Explicit JDK home to use. This must be the JDK home, not bin/java.",
    )
    parser.add_argument(
        "--gradlew",
        type=Path,
        default=DEFAULT_GRADLEW,
        help="Gradle wrapper to run.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only validate JDK discovery and print the Gradle command.",
    )
    parser.add_argument(
        "--verify-unchanged",
        action="store_true",
        help="After generation, fail if parity/corridor-core.json changed.",
    )
    parser.add_argument(
        "--no-system-discovery",
        action="store_true",
        help="Use only --java-home or JAVA_HOME candidates.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    candidates = discover_candidates(args)
    compatible = next((candidate for candidate in candidates if candidate.status == "compatible"), None)

    if compatible is None:
        print_json(build_blocked_result(candidates))
        return 2

    command = build_gradle_command(args.gradlew)
    ready_result = build_ready_result(compatible, command)
    if args.dry_run:
        print_json(ready_result)
        return 0

    env = os.environ.copy()
    env["JAVA_HOME"] = str(compatible.path)
    env["PATH"] = f"{compatible.path / 'bin'}{os.pathsep}{env.get('PATH', '')}"

    print_json(ready_result)
    result = subprocess.run(command, cwd=REPO_ROOT, env=env, check=False)
    if result.returncode != 0:
        return result.returncode

    if args.verify_unchanged:
        diff = subprocess.run(
            ["git", "diff", "--exit-code", "--", str(PARITY_FIXTURE.relative_to(REPO_ROOT))],
            cwd=REPO_ROOT,
            check=False,
        )
        return diff.returncode

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
