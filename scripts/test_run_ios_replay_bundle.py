#!/usr/bin/env python3
"""Tests for scripts/run-ios-replay-bundle.py."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("run-ios-replay-bundle.py")


def write_executable(path: Path, text: str) -> None:
    path.write_text(textwrap.dedent(text).lstrip(), encoding="utf-8")
    path.chmod(0o755)


class RunIosReplayBundleTest(unittest.TestCase):
    def test_bundle_writes_log_verify_and_label_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            video = root / "home clip.mp4"
            video.write_text("fixture", encoding="utf-8")
            replay = root / "fake-replay.py"
            verify = root / "fake-verify.py"
            label = root / "fake-label.py"
            out = root / "out"

            write_executable(
                replay,
                """
                #!/usr/bin/env python3
                print("roana_ios_replay status=started video=fixture.mp4 duration_s=2.00 fps=1.00 width=720 height=1280")
                print("roana_ios_motion_quality label=stable reason=motion_unavailable trusts_guidance=true source=replay")
                print("roana_ios_corridor decision=STOP state=STOP reason=near_obstacle path_cells=0 pending=none pending_count=0")
                print("roana_ios_replay status=finished frames=1")
                """,
            )
            write_executable(
                verify,
                """
                #!/usr/bin/env python3
                import json
                print(json.dumps({"status": "passed", "missing": [], "fixture": "stop"}))
                """,
            )
            write_executable(
                label,
                """
                #!/usr/bin/env python3
                import json
                import pathlib
                import sys
                args = sys.argv
                summary = pathlib.Path(args[args.index("--summary") + 1])
                data = {
                    "status": "passed",
                    "missing": [],
                    "fixture_suggestion": "stop",
                    "command_labels": ["STOP"],
                    "scene_quality_labels": ["too_close"],
                    "segments": [{"time_s": 1.0, "command": "STOP"}],
                }
                summary.write_text(json.dumps(data), encoding="utf-8")
                print(json.dumps(data))
                """,
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    str(video),
                    "--output-dir",
                    str(out),
                    "--timestamp",
                    "20260530T010203Z",
                    "--replay-bin",
                    str(replay),
                    "--verify-bin",
                    str(verify),
                    "--label-bin",
                    str(label),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            data = json.loads(result.stdout)
            self.assertEqual("", result.stderr)
            self.assertEqual(0, result.returncode, result.stdout)
            self.assertEqual("passed", data["status"])
            self.assertEqual([], data["missing"])
            self.assertEqual("stop", data["labels"]["fixtureSuggestion"])
            self.assertEqual(["STOP"], data["labels"]["commandLabels"])
            self.assertEqual(["too_close"], data["labels"]["sceneQualityLabels"])
            self.assertEqual(1, data["labels"]["segmentCount"])
            self.assertTrue(Path(data["artifacts"]["log"]).is_file())
            self.assertTrue(Path(data["artifacts"]["verify"]).is_file())
            self.assertTrue(Path(data["artifacts"]["labels"]).is_file())
            self.assertEqual("roana-ios-replay-home-clip-20260530T010203Z.log", Path(data["artifacts"]["log"]).name)

    def test_blocks_when_verifier_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            video = root / "clip.mp4"
            video.write_text("fixture", encoding="utf-8")
            replay = root / "fake-replay.py"
            verify = root / "fake-verify.py"
            label = root / "fake-label.py"

            write_executable(replay, "#!/usr/bin/env python3\nprint('roana_ios_replay status=finished frames=1')\n")
            write_executable(
                verify,
                """
                #!/usr/bin/env python3
                import json
                print(json.dumps({"status": "blocked", "missing": ["corridor_guidance_feedback"]}))
                raise SystemExit(2)
                """,
            )
            write_executable(
                label,
                """
                #!/usr/bin/env python3
                import json
                print(json.dumps({"status": "passed", "missing": [], "segments": []}))
                """,
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    str(video),
                    "--output-dir",
                    str(root / "out"),
                    "--timestamp",
                    "20260530T010203Z",
                    "--replay-bin",
                    str(replay),
                    "--verify-bin",
                    str(verify),
                    "--label-bin",
                    str(label),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            data = json.loads(result.stdout)
            self.assertEqual(2, result.returncode)
            self.assertEqual("blocked", data["status"])
            self.assertIn("replay_verification", data["missing"])
            self.assertIn("corridor_guidance_feedback", data["missing"])

    def test_blocks_when_video_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    str(Path(temp_dir) / "missing.mp4"),
                    "--output-dir",
                    str(Path(temp_dir) / "out"),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        data = json.loads(result.stdout)
        self.assertEqual(2, result.returncode)
        self.assertEqual("blocked", data["status"])
        self.assertEqual(["video_file"], data["missing"])


if __name__ == "__main__":
    unittest.main()
