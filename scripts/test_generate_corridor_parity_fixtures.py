#!/usr/bin/env python3
"""Tests for the corridor parity fixture generation wrapper."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("generate-corridor-parity-fixtures.py")


def make_fake_jdk(root: Path, major: int) -> Path:
    java_home = root / f"jdk-{major}"
    bin_dir = java_home / "bin"
    bin_dir.mkdir(parents=True)
    (java_home / "release").write_text(f'JAVA_VERSION="{major}.0.1"\n', encoding="utf-8")
    java = bin_dir / "java"
    java.write_text("#!/usr/bin/env sh\necho fake java\n", encoding="utf-8")
    java.chmod(java.stat().st_mode | stat.S_IXUSR)
    return java_home


def make_fake_gradlew(root: Path) -> Path:
    gradlew = root / "gradlew"
    gradlew.write_text(
        "#!/usr/bin/env sh\n"
        "printf '%s\\n' \"$JAVA_HOME\" > \"$GRADLEW_JAVA_HOME_OUT\"\n"
        "printf '%s\\n' \"$*\" > \"$GRADLEW_ARGS_OUT\"\n",
        encoding="utf-8",
    )
    gradlew.chmod(gradlew.stat().st_mode | stat.S_IXUSR)
    return gradlew


class GenerateCorridorParityFixturesTest(unittest.TestCase):
    def run_script(
        self,
        *args: str,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

    def test_dry_run_accepts_explicit_jdk_17_home(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            java_home = make_fake_jdk(Path(tmp), 17)

            result = self.run_script(
                "--java-home",
                str(java_home),
                "--dry-run",
                "--no-system-discovery",
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        details = json.loads(result.stdout)
        self.assertEqual(details["status"], "ready")
        self.assertEqual(details["javaMajor"], 17)
        self.assertIn(":app:generateCorridorParityFixtures", details["command"])

    def test_dry_run_rejects_java_home_that_points_to_bin_java(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            java_home = make_fake_jdk(Path(tmp), 17)

            result = self.run_script(
                "--java-home",
                str(java_home / "bin/java"),
                "--dry-run",
                "--no-system-discovery",
            )

        self.assertEqual(result.returncode, 2)
        details = json.loads(result.stdout)
        self.assertEqual(details["status"], "blocked")
        self.assertEqual(details["candidates"][0]["reason"], "java_home_points_to_executable")

    def test_dry_run_rejects_incompatible_jdk_25(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            java_home = make_fake_jdk(Path(tmp), 25)

            result = self.run_script(
                "--java-home",
                str(java_home),
                "--dry-run",
                "--no-system-discovery",
            )

        self.assertEqual(result.returncode, 2)
        details = json.loads(result.stdout)
        self.assertEqual(details["status"], "blocked")
        self.assertEqual(details["candidates"][0]["status"], "incompatible")
        self.assertEqual(details["candidates"][0]["major"], 25)

    def test_runs_gradle_with_selected_java_home(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            java_home = make_fake_jdk(root, 21)
            gradlew = make_fake_gradlew(root)
            java_home_out = root / "java-home.txt"
            args_out = root / "args.txt"
            env = os.environ.copy()
            env["GRADLEW_JAVA_HOME_OUT"] = str(java_home_out)
            env["GRADLEW_ARGS_OUT"] = str(args_out)

            result = self.run_script(
                "--java-home",
                str(java_home),
                "--gradlew",
                str(gradlew),
                "--no-system-discovery",
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            details = json.loads(result.stdout)
            self.assertEqual(details["status"], "ready")
            self.assertEqual(java_home_out.read_text(encoding="utf-8").strip(), str(java_home))
            self.assertEqual(
                args_out.read_text(encoding="utf-8").strip(),
                ":app:generateCorridorParityFixtures --no-daemon",
            )


if __name__ == "__main__":
    unittest.main()
