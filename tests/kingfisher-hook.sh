#!/usr/bin/env bash
# Exercise the documented installation and the bundled hook without a scanner,
# network access, real credentials, or changes to the developer's Git config.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - "${1:-}" <<'PY'
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

root = Path.cwd()
skill_dir = Path(sys.argv[1]).resolve() if sys.argv[1] else root / "skills/kingfisher"
guide = skill_dir / "references/kingfisher.md" if sys.argv[1] else root / "references/kingfisher.md"
section = guide.read_text().split(
    "### Standalone hook (no `pre-commit` framework)", 1
)[1]
install = section.split("```bash\n", 1)[1].split("```", 1)[0].replace(
    "skill_dir='<absolute directory containing the loaded Kingfisher SKILL.md>'",
    "skill_dir=" + shlex.quote(str(skill_dir)),
)


class HookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kingfisher-hook-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repository with spaces"
        self.repo.mkdir()
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        # Keep PATH deterministic, including the missing-scanner case.
        for command in ("bash", "git", "mkdir", "install"):
            (self.bin / command).symlink_to(shutil.which(command))
        self.env = dict(os.environ, PATH=str(self.bin), GIT_CONFIG_NOSYSTEM="1",
                        GIT_CONFIG_GLOBAL=os.devnull,
                        KF_TEST_ARGS=str(Path(self.temp.name) / "args"))
        # Inherited repository overrides must not target the developer's repo.
        for key in list(self.env):
            if key.startswith("GIT_") and key not in {
                "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL"
            }:
                del self.env[key]
        self.run_command(["git", "init", "--quiet"], check=True)
        self.hook = self.repo / ".git/hooks/pre-commit"

    def run_command(self, args, cwd=None, check=False):
        return subprocess.run(args, cwd=cwd or self.repo, env=self.env,
                              text=True, capture_output=True, check=check)

    def install_hook(self, cwd=None):
        # Exercise a paste into an interactive shell. A guard must not exit the
        # shell, and successful setup must not leave errexit/nounset enabled.
        script = 'setup_flags=$-\nsetup_options=$SHELLOPTS\n' + install + '''
printf 'KINGFISHER_SETUP_CONTINUED\\n'
if [ "$setup_flags" = "$-" ] && [ "$setup_options" = "$SHELLOPTS" ]; then
  printf 'KINGFISHER_SHELL_OPTIONS_UNCHANGED\\n'
fi
'''
        result = self.run_command(
            ["bash", "--noprofile", "--norc", "-i", "-c", script], cwd=cwd
        )
        self.assertIn("KINGFISHER_SETUP_CONTINUED", result.stdout)
        self.assertIn("KINGFISHER_SHELL_OPTIONS_UNCHANGED", result.stdout)
        return result

    def scanner(self):
        scanner = self.bin / "kingfisher"
        scanner.write_text('#!/usr/bin/env bash\n'
                           'printf "%s\\n" "$PWD" "$@" > "$KF_TEST_ARGS"\n'
                           'exit "${KF_TEST_EXIT:-0}"\n')
        scanner.chmod(0o755)

    def test_install_and_run_from_subdirectory(self):
        self.scanner()
        self.assertEqual(self.install_hook().returncode, 0)
        self.assertTrue(os.access(self.hook, os.X_OK))
        nested = self.repo / "nested"
        nested.mkdir()
        self.assertEqual(self.run_command([str(self.hook)], cwd=nested).returncode, 0)
        self.assertEqual(Path(self.env["KF_TEST_ARGS"]).read_text().splitlines(),
                         [str(self.repo.resolve()), "scan", ".", "--staged",
                          "--quiet", "--redact", "--no-update-check"])

    def test_scanner_exit_status_is_preserved(self):
        self.scanner()
        self.assertEqual(self.install_hook().returncode, 0)
        for status in (1, 200, 205):
            with self.subTest(status=status):
                self.env["KF_TEST_EXIT"] = str(status)
                self.assertEqual(self.run_command([str(self.hook)]).returncode, status)

    def test_missing_scanner_fails(self):
        self.assertEqual(self.install_hook().returncode, 0)
        result = self.run_command([str(self.hook)])
        self.assertEqual(result.returncode, 127)
        self.assertIn("not on PATH", result.stderr)

    def test_existing_hook_is_preserved(self):
        self.hook.write_text("existing hook\n")
        result = self.install_hook()
        self.assertEqual(result.returncode, 0)
        self.assertIn("Existing pre-commit hook", result.stderr)
        self.assertEqual(self.hook.read_text(), "existing hook\n")

    def test_dangling_hook_symlink_is_preserved(self):
        self.hook.symlink_to("missing-existing-hook")
        self.assertEqual(self.install_hook().returncode, 0)
        self.assertEqual(os.readlink(self.hook), "missing-existing-hook")

    def test_configured_hooks_path_is_preserved(self):
        shared = Path(self.temp.name) / "shared hooks"
        self.run_command(["git", "config", "core.hooksPath", str(shared)], check=True)
        result = self.install_hook()
        self.assertEqual(result.returncode, 0)
        self.assertIn("Existing core.hooksPath", result.stderr)
        self.assertFalse(shared.exists())
        self.assertFalse(self.hook.exists())

    def test_outside_repository_leaves_shell_running(self):
        result = self.install_hook(cwd=Path(self.temp.name))
        self.assertEqual(result.returncode, 0)
        self.assertIn("Run hook setup from a Git repository", result.stderr)
        self.assertFalse((Path(self.temp.name) / "pre-commit").exists())


unittest.main(argv=[sys.argv[0]], verbosity=2)
PY
