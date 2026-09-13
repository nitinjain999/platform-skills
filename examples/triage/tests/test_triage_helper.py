import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "scripts" / "triage_helper.py"


def load_helper_module():
    spec = importlib.util.spec_from_file_location("triage_helper_under_test", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

FAKE_GH_TEMPLATE = '''#!/usr/bin/env python3
import sys, os, json
rules = json.loads(os.environ["FAKE_GH_RULES"])
argv_line = " ".join(sys.argv[1:])
argv_log_path = os.environ.get("FAKE_GH_ARGV_LOG")
if argv_log_path:
    with open(argv_log_path, "a") as f:
        f.write(argv_line + "\\n")
if "--input" in sys.argv:
    idx = sys.argv.index("--input")
    input_path = sys.argv[idx + 1]
    try:
        with open(input_path, "r") as f:
            argv_line += " " + f.read()
    except:
        pass
log_path = os.environ.get("FAKE_GH_CALLS_LOG")
if log_path:
    with open(log_path, "a") as f:
        f.write(argv_line + "\\n")
uses_path = os.environ.get("FAKE_GH_USES")
uses = {}
if uses_path and os.path.exists(uses_path):
    try:
        with open(uses_path) as f:
            uses = json.load(f)
    except Exception:
        uses = {}
for index, rule in enumerate(rules):
    if not all(s in argv_line for s in rule["contains"]):
        continue
    max_uses = rule.get("max_uses")
    used = uses.get(str(index), 0)
    if max_uses is not None and used >= max_uses:
        continue
    if uses_path:
        uses[str(index)] = used + 1
        with open(uses_path, "w") as f:
            json.dump(uses, f)
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
    env["FAKE_GH_ARGV_LOG"] = str(tmp_path / "gh_argv.log")
    env["FAKE_GH_USES"] = str(tmp_path / "gh_rule_uses.json")
    return env, calls_log


class TestResolveIdentity(unittest.TestCase):
    def test_open_pr_same_repo_head(self):
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

    def test_fork_pr_head_repo_differs_from_base(self):
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

    def test_closed_pr_is_rejected(self):
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
    def test_review_comment_on_requested_pr(self):
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

    def test_comment_belongs_to_a_different_pr_is_refused(self):
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

    def test_review_comment_never_reports_a_rest_full_database_id(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{
            "contains": ["pulls/comments/555"],
            "stdout": {
                "node_id": "PRRC_kwbig", "id": 555, "pull_request_url": "https://api.github.com/repos/acme/widgets/pulls/42",
                "full_database_id": 9223372036854775800,
            },
        }]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(
            ["resolve-comment", "--repo", "acme/widgets", "--pr", "42", "--comment-id", "555"], env=env,
        )
        data = json.loads(result.stdout)
        self.assertIsNone(data["full_database_id"])
        self.assertEqual(data["database_id"], "555")

    def test_not_found_carries_both_lookup_failures(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [
            {"contains": ["pulls/comments/777"], "stdout": "", "returncode": 1, "stderr": "gh: HTTP 401 Bad credentials"},
            {"contains": ["issues/comments/777"], "stdout": "", "returncode": 1, "stderr": "gh: HTTP 500"},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(
            ["resolve-comment", "--repo", "acme/widgets", "--pr", "42", "--comment-id", "777"], env=env,
        )
        self.assertNotEqual(result.returncode, 0)
        error = json.loads(result.stdout)["error"]
        self.assertEqual(error["code"], "COMMENT_NOT_FOUND")
        self.assertEqual(error["review_lookup_returncode"], 1)
        self.assertIn("401", error["review_lookup_stderr"])
        self.assertEqual(error["issue_lookup_returncode"], 1)
        self.assertIn("500", error["issue_lookup_stderr"])

    def test_falls_back_to_issue_comment_when_review_lookup_404s(self):
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


class TestSnapshot(unittest.TestCase):
    def test_paginates_threads_across_two_pages(self):
        tmp_path = Path(tempfile.mkdtemp())
        page1 = {
            "data": {"repository": {"pullRequest": {"reviewThreads": {
                "pageInfo": {"hasNextPage": True, "endCursor": "CURSOR1"},
                "nodes": [{
                    "id": "PRT_1", "isResolved": False, "isOutdated": False,
                    "viewerCanReply": True, "viewerCanResolve": True,
                    "comments": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                 "nodes": [{"id": "PRRC_1", "databaseId": 11, "fullDatabaseId": 11,
                                            "body": "root", "path": "a.yml", "line": 3,
                                            "author": {"login": "alice"}, "updatedAt": "2026-01-01T00:00:00Z",
                                            "replyTo": None}]},
                }],
            }}}}
        }
        page2 = {
            "data": {"repository": {"pullRequest": {"reviewThreads": {
                "pageInfo": {"hasNextPage": False, "endCursor": None},
                "nodes": [{
                    "id": "PRT_2", "isResolved": True, "isOutdated": False,
                    "viewerCanReply": True, "viewerCanResolve": True,
                    "comments": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                 "nodes": [{"id": "PRRC_2", "databaseId": 22, "fullDatabaseId": 22,
                                            "body": "second thread", "path": "b.yml", "line": 1,
                                            "author": {"login": "bob"}, "updatedAt": "2026-01-02T00:00:00Z",
                                            "replyTo": None}]},
                }],
            }}}}
        }
        rules = [
            {"contains": ["repos/acme/widgets/pulls/42"], "stdout": {"head": {"sha": "a" * 40}}},
            {"contains": ["reviewThreads", "CURSOR1"], "stdout": page2},
            {"contains": ["reviewThreads"], "stdout": page1},
        ]
        env, calls_log = gh_env(tmp_path, rules)
        out_file = tmp_path / "snapshot.json"
        result = run_helper(
            ["snapshot", "--repo", "acme/widgets", "--pr", "42", "--out", str(out_file)], env=env,
        )
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(len(data["threads"]), 2)
        self.assertEqual(data["threads"][0]["comments"][0]["database_id"], "11")
        self.assertTrue(out_file.exists())

    def test_head_drift_is_reported_not_hidden(self):
        tmp_path = Path(tempfile.mkdtemp())
        empty_page = {"data": {"repository": {"pullRequest": {"reviewThreads": {
            "pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": [],
        }}}}}
        rules = [
            {"contains": ["reviewThreads"], "stdout": empty_page},
            {"contains": ["repos/acme/widgets/pulls/42"], "stdout": {"head": {"sha": "a" * 40}}, "max_uses": 1},
            {"contains": ["repos/acme/widgets/pulls/42"], "stdout": {"head": {"sha": "b" * 40}}},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["snapshot", "--repo", "acme/widgets", "--pr", "42"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["head_sha_before"], "a" * 40)
        self.assertEqual(data["head_sha_after"], "b" * 40)
        self.assertTrue(data["head_changed_during_collection"])

    def test_stable_head_reports_no_drift(self):
        tmp_path = Path(tempfile.mkdtemp())
        empty_page = {"data": {"repository": {"pullRequest": {"reviewThreads": {
            "pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": [],
        }}}}}
        rules = [
            {"contains": ["reviewThreads"], "stdout": empty_page},
            {"contains": ["repos/acme/widgets/pulls/42"], "stdout": {"head": {"sha": "b" * 40}}},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["snapshot", "--repo", "acme/widgets", "--pr", "42"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["head_sha_before"], "b" * 40)
        self.assertEqual(data["head_sha_after"], "b" * 40)
        self.assertFalse(data["head_changed_during_collection"])

    def test_large_full_database_id_from_graphql_stays_lossless(self):
        tmp_path = Path(tempfile.mkdtemp())
        big = 9223372036854775800
        page = {
            "data": {"repository": {"pullRequest": {"reviewThreads": {
                "pageInfo": {"hasNextPage": False, "endCursor": None},
                "nodes": [{
                    "id": "PRT_1", "isResolved": False, "isOutdated": False,
                    "viewerCanReply": True, "viewerCanResolve": True,
                    "comments": {"pageInfo": {"hasNextPage": False, "endCursor": None},
                                 "nodes": [{"id": "PRRC_1", "databaseId": 11, "fullDatabaseId": big,
                                            "body": "root", "path": "a.yml", "line": 3,
                                            "author": {"login": "alice"}, "updatedAt": "2026-01-01T00:00:00Z",
                                            "replyTo": None}]},
                }],
            }}}}
        }
        rules = [
            {"contains": ["repos/acme/widgets/pulls/42"], "stdout": {"head": {"sha": "a" * 40}}},
            {"contains": ["reviewThreads"], "stdout": page},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["snapshot", "--repo", "acme/widgets", "--pr", "42"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["threads"][0]["comments"][0]["full_database_id"], str(big))


class TestMapThread(unittest.TestCase):
    def _write_snapshot(self, tmp_path):
        snapshot = {
            "threads": [{
                "id": "PRT_1", "is_resolved": False, "viewer_can_reply": True, "viewer_can_resolve": True,
                "comments": [
                    {"node_id": "PRRC_root", "database_id": "11", "full_database_id": "11", "body": "root"},
                    {"node_id": "PRRC_reply", "database_id": "22", "full_database_id": "22", "body": "a reply"},
                ],
            }],
        }
        path = tmp_path / "snapshot.json"
        path.write_text(json.dumps(snapshot))
        return path

    def test_maps_a_reply_id_not_just_the_root(self):
        tmp_path = Path(tempfile.mkdtemp())
        snap = self._write_snapshot(tmp_path)
        result = run_helper(["map-thread", "--snapshot", str(snap), "--comment-id", "22"])
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["thread_node_id"], "PRT_1")
        self.assertFalse(data["is_root_comment"])

    def test_maps_the_root_id_too(self):
        tmp_path = Path(tempfile.mkdtemp())
        snap = self._write_snapshot(tmp_path)
        result = run_helper(["map-thread", "--snapshot", str(snap), "--comment-id", "11"])
        data = json.loads(result.stdout)
        self.assertTrue(data["is_root_comment"])

    def test_unmapped_comment_is_a_clear_error_not_silence(self):
        tmp_path = Path(tempfile.mkdtemp())
        snap = self._write_snapshot(tmp_path)
        result = run_helper(["map-thread", "--snapshot", str(snap), "--comment-id", "999"])
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "COMMENT_NOT_IN_SNAPSHOT")


class TestPatchContext(unittest.TestCase):
    def test_exact_filename_match_returns_patch_ok(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [[
            {"filename": "a.yml", "patch": "@@ -1 +1 @@\n-old\n+new"},
        ]]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "a.yml"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["evidence_status"], "PATCH_OK")

    def test_renamed_file_matches_previous_filename(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [[
            {"filename": "new-name.yaml", "previous_filename": "old-name.yaml", "patch": "@@ -1 +1 @@\n-x\n+y"},
        ]]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "old-name.yaml"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["evidence_status"], "RENAMED")
        self.assertEqual(data["filename"], "new-name.yaml")

    def test_binary_file_has_no_patch_but_explicit_status(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [[
            {"filename": "logo.png"},
        ]]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "logo.png"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["evidence_status"], "BINARY_OR_UNAVAILABLE")

    def test_missing_api_patch_falls_back_to_a_real_local_diff(self):
        tmp_path = Path(tempfile.mkdtemp())
        repo = tmp_path / "repo"
        repo.mkdir()
        subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "t@example.com"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
        (repo / "big.yml").write_text("replicas: 1\n")
        subprocess.run(["git", "add", "big.yml"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-m", "base"], cwd=repo, check=True, capture_output=True)
        base_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True).stdout.strip()
        (repo / "big.yml").write_text("replicas: 3\n")
        subprocess.run(["git", "commit", "-am", "bump"], cwd=repo, check=True, capture_output=True)
        head_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True).stdout.strip()

        rules = [{"contains": ["pulls/42/files"], "stdout": [[{"filename": "big.yml"}]]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "big.yml",
            "--base-sha", base_sha, "--head-sha", head_sha, "--repo-root", str(repo),
        ], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["evidence_status"], "LOCAL_DIFF_FALLBACK")
        self.assertIn("-replicas: 1", data["patch"])
        self.assertIn("+replicas: 3", data["patch"])

    def test_paginate_slurp_shape_is_flattened_across_pages(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [
            [{"filename": "a.yml", "patch": "@@ -1 +1 @@\n-old\n+new"}],
            [{"filename": "b.yml", "patch": "@@ -1 +1 @@\n-x\n+y"}],
        ]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "b.yml"], env=env)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"], data)
        self.assertEqual(data["evidence_status"], "PATCH_OK")
        self.assertEqual(data["filename"], "b.yml")

    def test_file_not_in_diff_at_all(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [[
            {"filename": "unrelated.yml", "patch": "@@ -1 +1 @@\n-x\n+y"},
        ]]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "missing.yml"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["evidence_status"], "NOT_IN_DIFF")


class TestWorktree(unittest.TestCase):
    def _make_repo(self, tmp_path):
        repo = tmp_path / "origin"
        repo.mkdir()
        subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "t@example.com"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
        (repo / "a.yml").write_text("original\n")
        subprocess.run(["git", "add", "a.yml"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=repo, check=True, capture_output=True)
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True).stdout.strip()
        return repo, sha

    def test_prepare_does_not_touch_original_dirty_files(self):
        tmp_path = Path(tempfile.mkdtemp())
        repo, sha = self._make_repo(tmp_path)
        (repo / "a.yml").write_text("dirty uncommitted edit\n")

        result = run_helper(["worktree", "prepare", "--repo-root", str(repo), "--head-sha", sha])
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        wt_path = Path(data["worktree_path"])

        self.assertEqual((repo / "a.yml").read_text(), "dirty uncommitted edit\n")
        self.assertEqual((wt_path / "a.yml").read_text(), "original\n")

        cleanup = run_helper(["worktree", "cleanup", "--repo-root", str(repo), "--path", str(wt_path)])
        self.assertTrue(json.loads(cleanup.stdout)["ok"])


class TestStageCommit(unittest.TestCase):
    def _prepared_worktree(self, tmp_path):
        repo, sha = TestWorktree()._make_repo(tmp_path)
        result = run_helper(["worktree", "prepare", "--repo-root", str(repo), "--head-sha", sha])
        return Path(json.loads(result.stdout)["worktree_path"])

    def test_commits_only_the_named_path(self):
        tmp_path = Path(tempfile.mkdtemp())
        wt = self._prepared_worktree(tmp_path)
        (wt / "a.yml").write_text("fixed\n")
        result = run_helper(["stage-commit", "--worktree", str(wt), "--paths", "a.yml", "--message", "fix: a"])
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["committed_paths"], ["a.yml"])

    def test_non_ascii_filename_is_not_a_false_mismatch(self):
        tmp_path = Path(tempfile.mkdtemp())
        wt = self._prepared_worktree(tmp_path)
        (wt / "café.yml").write_text("value: 1\n")
        result = run_helper(["stage-commit", "--worktree", str(wt), "--paths", "café.yml", "--message", "fix: café"])
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"], data)
        self.assertEqual(data["committed_paths"], ["café.yml"])

    def test_refuses_when_staged_set_has_extra_unrelated_file(self):
        tmp_path = Path(tempfile.mkdtemp())
        wt = self._prepared_worktree(tmp_path)
        (wt / "a.yml").write_text("fixed\n")
        (wt / "b.yml").write_text("unrelated new file\n")
        subprocess.run(["git", "add", "b.yml"], cwd=wt, check=True)
        result = run_helper(["stage-commit", "--worktree", str(wt), "--paths", "a.yml", "--message", "fix: a"])
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "STAGED_SET_MISMATCH")


class TestPublish(unittest.TestCase):
    def _remote_and_worktree(self, tmp_path):
        remote = tmp_path / "remote.git"
        subprocess.run(["git", "init", "--bare", str(remote)], check=True, capture_output=True)

        seed = tmp_path / "seed"
        seed.mkdir()
        subprocess.run(["git", "init"], cwd=seed, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "t@example.com"], cwd=seed, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=seed, check=True)
        (seed / "a.yml").write_text("original\n")
        subprocess.run(["git", "add", "a.yml"], cwd=seed, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=seed, check=True, capture_output=True)
        subprocess.run(["git", "remote", "add", "origin", str(remote)], cwd=seed, check=True)
        subprocess.run(["git", "push", "origin", "HEAD:refs/heads/fix-branch"], cwd=seed, check=True, capture_output=True)
        head_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=seed, capture_output=True, text=True).stdout.strip()

        wt = tempfile.mkdtemp()
        subprocess.run(["git", "worktree", "add", "--detach", wt, head_sha], cwd=seed, check=True, capture_output=True)
        (Path(wt) / "a.yml").write_text("fixed\n")
        subprocess.run(["git", "add", "a.yml"], cwd=wt, check=True)
        subprocess.run(["git", "commit", "-m", "fix"], cwd=wt, check=True, capture_output=True)
        commit_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=wt, capture_output=True, text=True).stdout.strip()
        return remote, wt, head_sha, commit_sha

    def test_publish_succeeds_when_remote_head_matches_expectation(self):
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        rules = [
            {"contains": ["pulls/42"], "stdout": {"head": {"sha": head_sha}}, "max_uses": 1},
            {"contains": ["pulls/42"], "stdout": {"head": {"sha": commit_sha}}},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", str(remote), "--head-ref", "fix-branch",
        ], env=env)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["remote_head_after"], commit_sha)
        self.assertEqual(data["pr_head_after"], commit_sha)
        self.assertTrue(data["matches_pushed_commit"])

    def test_publish_reports_mismatch_when_pr_head_disagrees_with_pushed_ref(self):
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        rules = [
            {"contains": ["pulls/42"], "stdout": {"head": {"sha": head_sha}}, "max_uses": 1},
            {"contains": ["pulls/42"], "stdout": {"head": {"sha": "f" * 40}}},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", str(remote), "--head-ref", "fix-branch",
        ], env=env)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["remote_head_after"], commit_sha)
        self.assertEqual(data["pr_head_after"], "f" * 40)
        self.assertFalse(data["matches_pushed_commit"])

    def test_publish_refuses_when_remote_pr_head_already_moved(self):
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        rules = [{"contains": ["pulls/42"], "stdout": {"head": {"sha": "f" * 40}}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", str(remote), "--head-ref", "fix-branch",
        ], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "HEAD_MOVED")

    def test_publish_never_uses_force(self):
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        other = tempfile.mkdtemp()
        subprocess.run(["git", "clone", str(remote), other], check=True, capture_output=True)
        subprocess.run(["git", "checkout", "fix-branch"], cwd=other, check=True, capture_output=True)
        (Path(other) / "a.yml").write_text("someone else's change\n")
        subprocess.run(["git", "add", "a.yml"], cwd=other, check=True)
        subprocess.run(["git", "-c", "user.email=x@x.com", "-c", "user.name=x", "commit", "-m", "divergent"], cwd=other, check=True, capture_output=True)
        subprocess.run(["git", "push", "origin", "fix-branch"], cwd=other, check=True, capture_output=True)

        rules = [{"contains": ["pulls/42"], "stdout": {"head": {"sha": head_sha}}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", str(remote), "--head-ref", "fix-branch",
        ], env=env)
        data = json.loads(result.stdout)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "PUSH_REJECTED_NON_FASTFORWARD")

    def test_non_fast_forward_with_permission_like_name_is_not_misclassified(self):
        # Regression: git push stderr always echoes the remote URL and ref
        # name. A repo named "permission-service.git" or a branch named
        # "fix/permissions-audit-403" must not cause a genuine non-fast-forward
        # rejection to be misread as NO_PUSH_PERMISSION just because the loose
        # "permission"/"403" substring check used to run before the
        # unambiguous non-fast-forward token check.
        tmp_path = Path(tempfile.mkdtemp())
        remote = tmp_path / "permission-service.git"
        subprocess.run(["git", "init", "--bare", str(remote)], check=True, capture_output=True)
        branch = "fix/permissions-audit-403"

        seed = tmp_path / "seed"
        seed.mkdir()
        subprocess.run(["git", "init"], cwd=seed, check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "t@example.com"], cwd=seed, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=seed, check=True)
        (seed / "a.yml").write_text("original\n")
        subprocess.run(["git", "add", "a.yml"], cwd=seed, check=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=seed, check=True, capture_output=True)
        subprocess.run(["git", "remote", "add", "origin", str(remote)], cwd=seed, check=True)
        subprocess.run(["git", "push", "origin", f"HEAD:refs/heads/{branch}"], cwd=seed, check=True, capture_output=True)
        head_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=seed, capture_output=True, text=True).stdout.strip()

        wt = tempfile.mkdtemp()
        subprocess.run(["git", "worktree", "add", "--detach", wt, head_sha], cwd=seed, check=True, capture_output=True)
        (Path(wt) / "a.yml").write_text("fixed\n")
        subprocess.run(["git", "add", "a.yml"], cwd=wt, check=True)
        subprocess.run(["git", "commit", "-m", "fix"], cwd=wt, check=True, capture_output=True)
        commit_sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=wt, capture_output=True, text=True).stdout.strip()

        # Someone else pushes a divergent commit to the same branch first, so
        # the worktree's push below is rejected as a genuine non-fast-forward.
        other = tempfile.mkdtemp()
        subprocess.run(["git", "clone", str(remote), other], check=True, capture_output=True)
        subprocess.run(["git", "checkout", branch], cwd=other, check=True, capture_output=True)
        (Path(other) / "a.yml").write_text("someone else's change\n")
        subprocess.run(["git", "add", "a.yml"], cwd=other, check=True)
        subprocess.run(["git", "-c", "user.email=x@x.com", "-c", "user.name=x", "commit", "-m", "divergent"], cwd=other, check=True, capture_output=True)
        subprocess.run(["git", "push", "origin", branch], cwd=other, check=True, capture_output=True)

        rules = [{"contains": ["pulls/42"], "stdout": {"head": {"sha": head_sha}}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", str(remote), "--head-ref", branch,
        ], env=env)
        data = json.loads(result.stdout)
        self.assertFalse(data["ok"])
        # Sanity check: the stderr genuinely contains the misleading tokens,
        # so this test would have failed against the pre-reorder classifier.
        stderr = data["error"]["stderr"]
        self.assertIn("permission", stderr.lower())
        self.assertIn("403", stderr)
        self.assertEqual(data["error"]["code"], "PUSH_REJECTED_NON_FASTFORWARD")

    def test_policy_rejection_is_not_reported_as_non_fast_forward(self):
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        hook = Path(remote) / "hooks" / "pre-receive"
        hook.write_text("#!/bin/sh\necho 'protected branch hook declined: fix-branch is protected' >&2\nexit 1\n")
        hook.chmod(0o755)

        rules = [{"contains": ["pulls/42"], "stdout": {"head": {"sha": head_sha}}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", str(remote), "--head-ref", "fix-branch",
        ], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "PUSH_REJECTED_BY_POLICY")

    def test_unreachable_remote_is_an_unknown_transport_failure(self):
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        rules = [{"contains": ["pulls/42"], "stdout": {"head": {"sha": head_sha}}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", str(tmp_path / "no-such-remote.git"), "--head-ref", "fix-branch",
        ], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "UNKNOWN_TRANSPORT_FAILURE")

    def test_tokenised_remote_url_is_redacted_from_error_output(self):
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        token_url = "https://x-access-token:ghs_SUPERSECRETVALUE@127.0.0.1:1/acme/widgets.git"
        rules = [{"contains": ["pulls/42"], "stdout": {"head": {"sha": head_sha}}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", token_url, "--head-ref", "fix-branch",
        ], env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("ghs_SUPERSECRETVALUE", result.stdout)
        self.assertNotIn("x-access-token", result.stdout)


class TestReply(unittest.TestCase):
    def test_thread_reply_preserves_literal_backticks_and_leading_at(self):
        tmp_path = Path(tempfile.mkdtemp())
        body_file = tmp_path / "body.txt"
        tricky_body = "Fixed `foo` @user $(rm -rf /) and `bar`. ✅ Fixed"
        body_file.write_text(tricky_body)

        rules = [{
            "contains": ["addPullRequestReviewThreadReply"],
            "stdout": {"data": {"addPullRequestReviewThreadReply": {"comment": {"id": "PRRC_new", "url": "https://x/1"}}}},
        }]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "reply", "--repo", "acme/widgets", "--thread-node-id", "PRT_1", "--body-file", str(body_file),
        ], env=env)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["status"], "CONFIRMED")
        argv_log = tmp_path / "gh_argv.log"
        logged_argv = argv_log.read_text() if argv_log.exists() else ""
        self.assertNotIn(tricky_body, logged_argv)

    def test_dedup_skips_a_repost_when_marker_already_present(self):
        tmp_path = Path(tempfile.mkdtemp())
        body_file = tmp_path / "body.txt"
        body_file.write_text("Fixed. <!-- triage:marker:abc123 --> ✅ Fixed")
        snapshot = {"threads": [{"id": "PRT_1", "comments": [
            {"node_id": "PRRC_x", "body": "Fixed already. <!-- triage:marker:abc123 --> ✅ Fixed"},
        ]}]}
        snap_path = tmp_path / "snapshot.json"
        snap_path.write_text(json.dumps(snapshot))
        env, calls_log = gh_env(tmp_path, [])
        result = run_helper([
            "reply", "--repo", "acme/widgets", "--thread-node-id", "PRT_1", "--body-file", str(body_file),
            "--snapshot", str(snap_path), "--dedup-marker", "triage:marker:abc123",
        ], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "ALREADY_REPLIED")
        self.assertFalse(calls_log.exists())

    def test_conversation_comment_reply_uses_input_payload(self):
        tmp_path = Path(tempfile.mkdtemp())
        body_file = tmp_path / "body.txt"
        tricky_body = "@user see `foo` $(rm -rf /) and `bar`. ❌ Not applicable."
        body_file.write_text(tricky_body)
        rules = [{"contains": ["issues/42/comments"], "stdout": {"id": 900, "html_url": "https://x/2"}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "reply", "--repo", "acme/widgets", "--pr", "42", "--body-file", str(body_file),
        ], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "CONFIRMED")
        self.assertEqual(data["comment_id"], "900")
        argv_log = tmp_path / "gh_argv.log"
        logged_argv = argv_log.read_text() if argv_log.exists() else ""
        self.assertNotIn(tricky_body, logged_argv)
        self.assertIn("--input", logged_argv)

    def test_reply_without_thread_or_pr_is_refused_before_any_call(self):
        tmp_path = Path(tempfile.mkdtemp())
        body_file = tmp_path / "body.txt"
        body_file.write_text("orphan reply")
        env, calls_log = gh_env(tmp_path, [])
        result = run_helper(["reply", "--repo", "acme/widgets", "--body-file", str(body_file)], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "INVALID_ARGUMENTS")
        self.assertFalse(calls_log.exists())

    def test_dedup_marker_without_a_thread_node_id_is_refused(self):
        tmp_path = Path(tempfile.mkdtemp())
        body_file = tmp_path / "body.txt"
        body_file.write_text("conversation reply")
        env, calls_log = gh_env(tmp_path, [])
        result = run_helper([
            "reply", "--repo", "acme/widgets", "--pr", "42", "--body-file", str(body_file),
            "--dedup-marker", "triage:marker:abc123",
        ], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "INVALID_ARGUMENTS")
        self.assertFalse(calls_log.exists())


class TestResolveThread(unittest.TestCase):
    def test_resolves_and_confirms_isresolved_true(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [
            {"contains": ["resolveReviewThread"], "stdout": {"data": {"resolveReviewThread": {"thread": {"isResolved": True}}}}},
            {"contains": ["viewerCanResolve"], "stdout": {"data": {"node": {"isResolved": False, "viewerCanResolve": True}}}},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["resolve-thread", "--thread-node-id", "PRT_1"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "CONFIRMED")

    def test_already_resolved_is_idempotent_no_mutation_call(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["viewerCanResolve"], "stdout": {"data": {"node": {"isResolved": True, "viewerCanResolve": True}}}}]
        env, calls_log = gh_env(tmp_path, rules)
        result = run_helper(["resolve-thread", "--thread-node-id", "PRT_1"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "ALREADY_RESOLVED")
        self.assertNotIn("resolveReviewThread", calls_log.read_text())

    def test_missing_resolve_permission_raises_not_authorized(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["viewerCanResolve"], "stdout": {"data": {"node": {"isResolved": False, "viewerCanResolve": False}}}}]
        env, calls_log = gh_env(tmp_path, rules)
        result = run_helper(["resolve-thread", "--thread-node-id", "PRT_1"], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "NOT_AUTHORIZED")
        self.assertNotIn("resolveReviewThread", calls_log.read_text())

    def test_empty_precheck_node_is_a_clear_error_not_a_crash(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["viewerCanResolve"], "stdout": {"data": {"node": None}}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["resolve-thread", "--thread-node-id", "PRRC_not_a_thread"], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "THREAD_NOT_FOUND")

    def test_snapshot_comment_count_drift_blocks_resolution(self):
        tmp_path = Path(tempfile.mkdtemp())
        snapshot = {"threads": [{"id": "PRT_1", "comments": [{"node_id": "PRRC_1", "body": "root"}]}]}
        snap_path = tmp_path / "snapshot.json"
        snap_path.write_text(json.dumps(snapshot))
        rules = [{"contains": ["viewerCanResolve"], "stdout": {"data": {"node": {
            "isResolved": False, "viewerCanResolve": True, "comments": {"totalCount": 2},
        }}}}]
        env, calls_log = gh_env(tmp_path, rules)
        result = run_helper([
            "resolve-thread", "--thread-node-id", "PRT_1", "--snapshot", str(snap_path),
        ], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "THREAD_CHANGED_SINCE_SNAPSHOT")
        self.assertEqual(data["error"]["expected_comment_count"], 1)
        self.assertEqual(data["error"]["actual_comment_count"], 2)
        self.assertNotIn("resolveReviewThread", calls_log.read_text())

    def test_mutation_result_false_is_not_treated_as_success(self):
        tmp_path = Path(tempfile.mkdtemp())
        rules = [
            {"contains": ["resolveReviewThread"], "stdout": {"data": {"resolveReviewThread": {"thread": {"isResolved": False}}}}},
            {"contains": ["viewerCanResolve"], "stdout": {"data": {"node": {"isResolved": False, "viewerCanResolve": True}}}},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["resolve-thread", "--thread-node-id", "PRT_1"], env=env)
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "RESOLVE_NOT_CONFIRMED")


class TestState(unittest.TestCase):
    def test_lock_then_second_lock_is_refused(self):
        tmp_path = Path(tempfile.mkdtemp())
        repo_root = tmp_path / "repo"
        (repo_root / ".git").mkdir(parents=True)
        first = run_helper(["state", "lock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertTrue(json.loads(first.stdout)["ok"])
        second = run_helper(["state", "lock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(json.loads(second.stdout)["error"]["code"], "LOCK_HELD")
        unlock = run_helper(["state", "unlock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertTrue(json.loads(unlock.stdout)["ok"])
        third = run_helper(["state", "lock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertTrue(json.loads(third.stdout)["ok"])

    def test_lock_held_error_names_the_holder(self):
        tmp_path = Path(tempfile.mkdtemp())
        repo_root = tmp_path / "repo"
        (repo_root / ".git").mkdir(parents=True)
        first = run_helper(["state", "lock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertTrue(json.loads(first.stdout)["ok"])
        second = run_helper(["state", "lock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        error = json.loads(second.stdout)["error"]
        self.assertEqual(error["code"], "LOCK_HELD")
        self.assertIsInstance(error["held_by_pid"], int)
        self.assertIsInstance(error["held_since"], float)
        self.assertIsInstance(error["age_seconds"], float)
        self.assertGreaterEqual(error["age_seconds"], 0)
        self.assertNotIn("confirming held_by_pid is not running", error["message"])

    def test_unrecognized_lock_needs_force_unlock(self):
        tmp_path = Path(tempfile.mkdtemp())
        repo_root = tmp_path / "repo"
        (repo_root / ".git" / "triage-state").mkdir(parents=True)
        lock = repo_root / ".git" / "triage-state" / "acme__widgets-42.lock"
        lock.write_text("not json written by this helper")
        refused = run_helper(["state", "unlock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertNotEqual(refused.returncode, 0)
        self.assertEqual(json.loads(refused.stdout)["error"]["code"], "LOCK_NOT_RECOGNIZED")
        self.assertTrue(lock.exists())
        forced = run_helper([
            "state", "unlock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42", "--force-unlock",
        ])
        data = json.loads(forced.stdout)
        self.assertTrue(data["ok"])
        self.assertTrue(data["forced"])
        self.assertFalse(lock.exists())

    def test_linked_worktree_repo_root_is_a_clear_error(self):
        tmp_path = Path(tempfile.mkdtemp())
        repo_root = tmp_path / "linked-worktree"
        repo_root.mkdir()
        (repo_root / ".git").write_text("gitdir: /somewhere/.git/worktrees/triage\n")
        result = run_helper(["state", "lock", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "REPO_ROOT_IS_LINKED_WORKTREE")

    def test_write_then_read_round_trips(self):
        tmp_path = Path(tempfile.mkdtemp())
        repo_root = tmp_path / "repo"
        (repo_root / ".git").mkdir(parents=True)
        record_file = tmp_path / "record.json"
        record_file.write_text(json.dumps({"findings": [{"id": "T01", "status": "PLANNED"}]}))
        write = run_helper(["state", "write", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42", "--record-file", str(record_file)])
        self.assertTrue(json.loads(write.stdout)["ok"])
        read = run_helper(["state", "read", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        data = json.loads(read.stdout)
        self.assertTrue(data["exists"])
        self.assertEqual(data["record"]["findings"][0]["id"], "T01")

    def test_read_rejects_state_written_for_a_different_pr_number(self):
        tmp_path = Path(tempfile.mkdtemp())
        repo_root = tmp_path / "repo"
        (repo_root / ".git" / "triage-state").mkdir(parents=True)
        corrupted = repo_root / ".git" / "triage-state" / "acme__widgets-42.json"
        corrupted.write_text(json.dumps({"schema_version": 1, "repo": "acme/widgets", "pr_number": 999}))
        read = run_helper(["state", "read", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertNotEqual(read.returncode, 0)
        self.assertEqual(json.loads(read.stdout)["error"]["code"], "STALE_OR_WRONG_STATE")


class TestRedaction(unittest.TestCase):
    def test_userinfo_is_stripped_from_any_url_in_error_text(self):
        redact = load_helper_module().redact
        self.assertEqual(
            redact("git ls-remote https://x-access-token:ghs_SECRET@github.com/acme/widgets.git failed"),
            "git ls-remote https://github.com/acme/widgets.git failed",
        )
        self.assertNotIn("ghs_SECRET", redact(
            "fatal: unable to access 'https://x-access-token:ghs_SECRET@github.com/acme/widgets.git/'",
        ))
        self.assertEqual(redact("git@github.com:acme/widgets.git"), "git@github.com:acme/widgets.git")
        self.assertIsNone(redact(None))


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
