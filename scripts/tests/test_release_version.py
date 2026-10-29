"""Exercise release orchestration with real Git repos and stubbed external services.

Run with: python3 -m unittest discover -s scripts/tests -v
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[2]
VERSION_FILE = "Sources/SloppyCore/SloppyCore.swift"


class ReleaseVersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.repo = root / "source"
        self.repo.mkdir()
        self.remote = root / "remote.git"
        self.log = root / "calls"
        self.env = dict(os.environ, RELEASE_TEST_LOG=str(self.log))
        self.env.pop("JUST_UNSTABLE", None)
        self.run_command("git", "init", "--bare", str(self.remote))
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.hooksPath", str(root / "no-hooks"))
        origin = "git@github.com:sglavoie/AI-Sloppy-Paste.git"
        self.git("remote", "add", "origin", origin)
        self.git("config", f"url.{self.remote}.insteadOf", origin)
        # get-url expands insteadOf; retain the production URL in its output.
        self.bin = root / "bin"
        self.bin.mkdir()
        real_git = shutil.which("git")
        self.write_script(self.bin / "git", f"""
if [[ "$*" == 'remote get-url origin' ]]; then
    printf '%s\\n' '{origin}'
else
    exec '{real_git}' "$@"
fi
""")
        self.write_script(self.bin / "gh", """
if [[ "$1" == auth ]]; then exit 0; fi
[[ "${RELEASE_TEST_EXISTS:-0}" == 1 ]]
""")
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]
        (self.repo / "scripts").mkdir()
        shutil.copy(PROJECT / "justfile", self.repo)
        shutil.copy(PROJECT / "scripts/release-version.sh", self.repo / "scripts")
        source = self.repo / VERSION_FILE
        source.parent.mkdir(parents=True)
        source.write_text('public enum SloppyCore {\n    public static let version = "1.2.3"\n}\n')
        (self.repo / ".gitignore").write_text(".build/\n")
        self.write_script(self.repo / "scripts/release.sh", """
printf 'prepare %s\\n' "$(just --evaluate version)" >> "$RELEASE_TEST_LOG"
[[ "${RELEASE_TEST_BUILD_FAIL:-0}" != 1 ]]
""")
        self.write_script(self.repo / "scripts/publish.sh", """
[[ "$(git rev-parse HEAD)" == "$(git ls-remote origin refs/heads/main | cut -f1)" ]]
printf 'publish %s\\n' "$1" >> "$RELEASE_TEST_LOG"
""")
        self.git("add", ".")
        self.git("commit", "-m", "Initial source")
        self.git("push", "origin", "main")
        self.initial = self.git("rev-parse", "HEAD").stdout.strip()

    @staticmethod
    def write_script(path, body):
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)

    def run_command(self, *args, check=True):
        return subprocess.run(args, cwd=self.repo, env=self.env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)

    def git(self, *args):
        return self.run_command("git", *args)

    def release(self, *args):
        return self.run_command("just", "release", *args, check=False)

    def remote_head(self):
        return self.git("ls-remote", "origin", "refs/heads/main").stdout.split()[0]

    def assert_untouched(self):
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.initial)
        self.assertEqual(self.remote_head(), self.initial)
        self.assertFalse(self.log.exists())

    def test_bumps_commit_and_publish_in_order(self):
        for bump, expected in (("patch", "1.2.4"), ("minor", "1.3.0"), ("major", "2.0.0")):
            with self.subTest(bump=bump):
                self.git("reset", "--hard", self.initial)
                self.git("push", "--force", "origin", "main")
                self.log.unlink(missing_ok=True)
                notes = "Fix user's search: `literal` $(touch .build/injected)\nSecond line"
                result = self.release(bump, notes)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.log.read_text(), f"prepare {expected}\npublish {notes}\n")
                self.assertIn(f'"{expected}"', (self.repo / VERSION_FILE).read_text())
                self.assertEqual(self.git("log", "-1", "--format=%s").stdout.strip(),
                                 f"chore(release): v{expected}")
                self.assertEqual(self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").stdout.strip(),
                                 VERSION_FILE)
                self.assertEqual(self.git("status", "--porcelain").stdout, "")
                self.assertEqual(self.remote_head(), self.git("rev-parse", "HEAD").stdout.strip())
                self.assertFalse((self.repo / ".build/injected").exists())

    def test_bare_release_only_prepares(self):
        result = self.release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text(), "prepare 1.2.3\n")
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.initial)
        self.assertEqual(self.remote_head(), self.initial)

    def test_invalid_bump_does_nothing(self):
        self.assertNotEqual(self.release("invalid").returncode, 0)
        self.assert_untouched()

    def test_dirty_tree_does_nothing(self):
        (self.repo / "uncommitted.txt").write_text("work in progress")
        self.assertNotEqual(self.release("patch").returncode, 0)
        self.assert_untouched()

    def test_wrong_branch_does_nothing(self):
        self.git("checkout", "-b", "feature")
        self.assertNotEqual(self.release("patch").returncode, 0)
        self.assert_untouched()

    def test_behind_main_does_nothing(self):
        self.git("commit", "--allow-empty", "-m", "Remote work")
        self.git("push", "origin", "main")
        remote = self.remote_head()
        self.git("reset", "--hard", self.initial)
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("behind or diverged", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.initial)
        self.assertEqual(self.remote_head(), remote)
        self.assertFalse(self.log.exists())

    def test_existing_release_does_nothing(self):
        self.env["RELEASE_TEST_EXISTS"] = "1"
        self.assertNotEqual(self.release("patch").returncode, 0)
        self.assert_untouched()

    def test_failed_build_keeps_version_without_pushing(self):
        self.env["RELEASE_TEST_BUILD_FAIL"] = "1"
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Do not bump again", result.stderr)
        self.assertEqual(self.log.read_text(), "prepare 1.2.4\n")
        self.assertIn('"1.2.4"', (self.repo / VERSION_FILE).read_text())
        self.assertEqual(self.remote_head(), self.initial)
        # Resume the committed version with the documented individual steps.
        del self.env["RELEASE_TEST_BUILD_FAIL"]
        self.assertEqual(self.release().returncode, 0)
        self.git("push", "origin", "main")
        self.run_command("just", "publish", "Retry notes")
        self.assertEqual(self.log.read_text(), "prepare 1.2.4\nprepare 1.2.4\npublish Retry notes\n")

    def test_failed_push_does_not_publish(self):
        self.write_script(self.remote / "hooks/pre-receive", "exit 1\n")
        result = self.release("patch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("git push origin main && just publish", result.stderr)
        self.assertEqual(self.log.read_text(), "prepare 1.2.4\n")
        self.assertEqual(self.remote_head(), self.initial)


if __name__ == "__main__":
    unittest.main()
