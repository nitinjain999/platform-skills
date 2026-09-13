import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "scripts" / "triage_helper.py"

FAKE_GH_TEMPLATE = '''#!/usr/bin/env python3
import sys, os, json
rules = json.loads(os.environ["FAKE_GH_RULES"])
argv_line = " ".join(sys.argv[1:])
log_path = os.environ.get("FAKE_GH_CALLS_LOG")
if log_path:
    with open(log_path, "a") as f:
        f.write(argv_line + "\\n")
for rule in rules:
    if all(s in argv_line for s in rule["contains"]):
        stdout = rule.get("stdout", "")
        if isinstance(stdout, (dict, list)):
            stdout = json.dumps(stdout)
        sys.stdout.write(stdout)
        sys.stderr.write(rule.get("stderr", ""))
        sys.exit(rule.get("returncode", 0))
sys.stderr.write("fake_gh: no rule matched: " + argv_line + "\\n")
sys.exit(99)
'''


def run_helper(args, cwd=None, env=None):
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    result = subprocess.run(
        [sys.executable, str(HELPER)] + args,
        cwd=cwd, env=full_env, capture_output=True, text=True,
    )
    return result


def make_fake_gh(tmp_path, rules):
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir(exist_ok=True)
    gh_path = bin_dir / "gh"
    gh_path.write_text(FAKE_GH_TEMPLATE)
    gh_path.chmod(0o755)
    return bin_dir


def gh_env(tmp_path, rules):
    bin_dir = make_fake_gh(tmp_path, rules)
    calls_log = tmp_path / "gh_calls.log"
    env = dict(os.environ)
    env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
    env["FAKE_GH_RULES"] = json.dumps(rules)
    env["FAKE_GH_CALLS_LOG"] = str(calls_log)
    return env, calls_log


class TestResolveIdentity(unittest.TestCase):
    def test_open_pr_same_repo_head(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{
            "contains": ["repos/acme/widgets/pulls/42"],
            "stdout": {
                "state": "open", "draft": False,
                "base": {"repo": {"full_name": "acme/widgets"}},
                "head": {"repo": {"full_name": "acme/widgets"}, "ref": "fix-42", "sha": "a" * 40},
            },
        }]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["resolve-identity", "--pr", "42", "--repo", "acme/widgets"], env=env)
        self.assertEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["head_sha"], "a" * 40)
        self.assertFalse(data["is_fork"])
        self.assertFalse(data["is_draft"])

    def test_fork_pr_head_repo_differs_from_base(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{
            "contains": ["repos/acme/widgets/pulls/7"],
            "stdout": {
                "state": "open", "draft": True,
                "base": {"repo": {"full_name": "acme/widgets"}},
                "head": {"repo": {"full_name": "contributor/widgets"}, "ref": "patch-1", "sha": "b" * 40},
            },
        }]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["resolve-identity", "--pr", "7", "--repo", "acme/widgets"], env=env)
        data = json.loads(result.stdout)
        self.assertTrue(data["is_fork"])
        self.assertTrue(data["is_draft"])
        self.assertEqual(data["state"], "open")

    def test_closed_pr_is_rejected(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{
            "contains": ["repos/acme/widgets/pulls/99"],
            "stdout": {
                "state": "closed", "draft": False,
                "base": {"repo": {"full_name": "acme/widgets"}},
                "head": {"repo": {"full_name": "acme/widgets"}, "ref": "old", "sha": "c" * 40},
            },
        }]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["resolve-identity", "--pr", "99", "--repo", "acme/widgets"], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "PR_NOT_OPEN")


class TestResolveComment(unittest.TestCase):
    def test_review_comment_on_requested_pr(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{
            "contains": ["pulls/comments/555"],
            "stdout": {
                "node_id": "PRRC_kw123", "id": 555, "pull_request_url": "https://api.github.com/repos/acme/widgets/pulls/42",
            },
        }]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(
            ["resolve-comment", "--repo", "acme/widgets", "--pr", "42", "--comment-id", "555"], env=env,
        )
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["comment_type"], "review")
        self.assertEqual(data["database_id"], "555")
        self.assertTrue(data["belongs_to_pr"])

    def test_comment_belongs_to_a_different_pr_is_refused(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{
            "contains": ["pulls/comments/555"],
            "stdout": {
                "node_id": "PRRC_kw123", "id": 555, "pull_request_url": "https://api.github.com/repos/acme/widgets/pulls/99",
            },
        }]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(
            ["resolve-comment", "--repo", "acme/widgets", "--pr", "42", "--comment-id", "555"], env=env,
        )
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "COMMENT_WRONG_PR")

    def test_large_id_beyond_js_safe_integer_stays_lossless(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        big = 9223372036854775800  # beyond Number.MAX_SAFE_INTEGER
        rules = [{
            "contains": ["pulls/comments/555"],
            "stdout": {
                "node_id": "PRRC_kwbig", "id": 555, "pull_request_url": "https://api.github.com/repos/acme/widgets/pulls/42",
                "full_database_id": big,
            },
        }]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(
            ["resolve-comment", "--repo", "acme/widgets", "--pr", "42", "--comment-id", "555"], env=env,
        )
        data = json.loads(result.stdout)
        self.assertEqual(data["full_database_id"], str(big))

    def test_falls_back_to_issue_comment_when_review_lookup_404s(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [
            {"contains": ["pulls/comments/777"], "stdout": "", "returncode": 1, "stderr": "404"},
            {"contains": ["issues/comments/777"], "stdout": {
                "node_id": "IC_kwxyz", "id": 777, "html_url": "https://github.com/acme/widgets/pull/42#issuecomment-777",
            }},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(
            ["resolve-comment", "--repo", "acme/widgets", "--pr", "42", "--comment-id", "777"], env=env,
        )
        data = json.loads(result.stdout)
        self.assertEqual(data["comment_type"], "issue")


class TestHelperSkeleton(unittest.TestCase):
    def test_help_exits_zero(self):
        result = run_helper(["--help"])
        self.assertEqual(result.returncode, 0)

    def test_unknown_command_emits_json_error_not_traceback(self):
        result = run_helper(["not-a-real-subcommand"])
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Traceback", result.stderr)

    def test_missing_required_arg_still_argparse_usage_not_crash(self):
        result = run_helper(["resolve-identity"])
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Traceback", result.stderr)
        data = json.loads(result.stdout)
        self.assertFalse(data["ok"])

    def test_subcommand_missing_required_flag_emits_json_not_empty_stdout(self):
        result = run_helper(["resolve-identity", "--pr", "1"])
        self.assertEqual(result.returncode, 2)
        data = json.loads(result.stdout)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "ARGUMENT_ERROR")


if __name__ == "__main__":
    unittest.main()
