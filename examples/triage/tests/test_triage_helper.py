import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "scripts" / "triage_helper.py"

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
    env["FAKE_GH_ARGV_LOG"] = str(tmp_path / "gh_argv.log")
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
        big = 9223372036854775800
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


class TestSnapshot(unittest.TestCase):
    def test_paginates_threads_across_two_pages(self, tmp_path=None):
        import tempfile
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

    def test_head_drift_is_reported_not_hidden(self, tmp_path=None):
        import tempfile
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
        self.assertIn("head_changed_during_collection", data)
        self.assertEqual(data["head_sha_before"], "b" * 40)
        self.assertEqual(data["head_sha_after"], "b" * 40)


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

    def test_maps_a_reply_id_not_just_the_root(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        snap = self._write_snapshot(tmp_path)
        result = run_helper(["map-thread", "--snapshot", str(snap), "--comment-id", "22"])
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["thread_node_id"], "PRT_1")
        self.assertFalse(data["is_root_comment"])

    def test_maps_the_root_id_too(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        snap = self._write_snapshot(tmp_path)
        result = run_helper(["map-thread", "--snapshot", str(snap), "--comment-id", "11"])
        data = json.loads(result.stdout)
        self.assertTrue(data["is_root_comment"])

    def test_unmapped_comment_is_a_clear_error_not_silence(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        snap = self._write_snapshot(tmp_path)
        result = run_helper(["map-thread", "--snapshot", str(snap), "--comment-id", "999"])
        self.assertNotEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["error"]["code"], "COMMENT_NOT_IN_SNAPSHOT")


class TestPatchContext(unittest.TestCase):
    def test_exact_filename_match_returns_patch_ok(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [
            {"filename": "a.yml", "patch": "@@ -1 +1 @@\n-old\n+new"},
        ]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "a.yml"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["evidence_status"], "PATCH_OK")

    def test_renamed_file_matches_previous_filename(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [
            {"filename": "new-name.yaml", "previous_filename": "old-name.yaml", "patch": "@@ -1 +1 @@\n-x\n+y"},
        ]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "old-name.yaml"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["evidence_status"], "RENAMED")
        self.assertEqual(data["filename"], "new-name.yaml")

    def test_binary_file_has_no_patch_but_explicit_status(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [
            {"filename": "logo.png"},
        ]}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["patch-context", "--repo", "acme/widgets", "--pr", "42", "--path", "logo.png"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["evidence_status"], "BINARY_OR_UNAVAILABLE")

    def test_file_not_in_diff_at_all(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["pulls/42/files"], "stdout": [
            {"filename": "unrelated.yml", "patch": "@@ -1 +1 @@\n-x\n+y"},
        ]}]
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

    def test_prepare_does_not_touch_original_dirty_files(self, tmp_path=None):
        import tempfile
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

    def test_commits_only_the_named_path(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        wt = self._prepared_worktree(tmp_path)
        (wt / "a.yml").write_text("fixed\n")
        result = run_helper(["stage-commit", "--worktree", str(wt), "--paths", "a.yml", "--message", "fix: a"])
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["committed_paths"], ["a.yml"])

    def test_refuses_when_staged_set_has_extra_unrelated_file(self, tmp_path=None):
        import tempfile
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

    def test_publish_succeeds_when_remote_head_matches_expectation(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        rules = [{"contains": ["pulls/42"], "stdout": {"head": {"sha": head_sha}}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "publish", "--repo", "acme/widgets", "--pr", "42", "--worktree", wt,
            "--expected-head-sha", head_sha, "--commit-sha", commit_sha,
            "--head-remote-url", str(remote), "--head-ref", "fix-branch",
        ], env=env)
        data = json.loads(result.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["remote_head_after"], commit_sha)

    def test_publish_refuses_when_remote_pr_head_already_moved(self, tmp_path=None):
        import tempfile
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

    def test_publish_never_uses_force(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        remote, wt, head_sha, commit_sha = self._remote_and_worktree(tmp_path)
        subprocess.run(["git", "push", str(remote), "HEAD~0:refs/heads/other-marker"], cwd=wt, check=False, capture_output=True)
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


class TestReply(unittest.TestCase):
    def test_thread_reply_preserves_literal_backticks_and_leading_at(self, tmp_path=None):
        import tempfile
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

    def test_dedup_skips_a_repost_when_marker_already_present(self, tmp_path=None):
        import tempfile
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

    def test_conversation_comment_reply_uses_input_payload(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        body_file = tmp_path / "body.txt"
        body_file.write_text("Not applicable here. ❌ Not applicable.")
        rules = [{"contains": ["issues/42/comments"], "stdout": {"id": 900, "html_url": "https://x/2"}}]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper([
            "reply", "--repo", "acme/widgets", "--pr", "42", "--body-file", str(body_file),
        ], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "CONFIRMED")
        self.assertEqual(data["comment_id"], "900")


class TestResolveThread(unittest.TestCase):
    def test_resolves_and_confirms_isresolved_true(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [
            {"contains": ["resolveReviewThread"], "stdout": {"data": {"resolveReviewThread": {"thread": {"isResolved": True}}}}},
            {"contains": ["viewerCanResolve"], "stdout": {"data": {"node": {"isResolved": False, "viewerCanResolve": True}}}},
        ]
        env, _ = gh_env(tmp_path, rules)
        result = run_helper(["resolve-thread", "--thread-node-id", "PRT_1"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "CONFIRMED")

    def test_already_resolved_is_idempotent_no_mutation_call(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        rules = [{"contains": ["viewerCanResolve"], "stdout": {"data": {"node": {"isResolved": True, "viewerCanResolve": True}}}}]
        env, calls_log = gh_env(tmp_path, rules)
        result = run_helper(["resolve-thread", "--thread-node-id", "PRT_1"], env=env)
        data = json.loads(result.stdout)
        self.assertEqual(data["status"], "ALREADY_RESOLVED")
        self.assertNotIn("resolveReviewThread", calls_log.read_text())

    def test_mutation_result_false_is_not_treated_as_success(self, tmp_path=None):
        import tempfile
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
    def test_lock_then_second_lock_is_refused(self, tmp_path=None):
        import tempfile
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

    def test_write_then_read_round_trips(self, tmp_path=None):
        import tempfile
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

    def test_read_rejects_state_written_for_a_different_pr_number(self, tmp_path=None):
        import tempfile
        tmp_path = Path(tempfile.mkdtemp())
        repo_root = tmp_path / "repo"
        (repo_root / ".git" / "triage-state").mkdir(parents=True)
        corrupted = repo_root / ".git" / "triage-state" / "acme__widgets-42.json"
        corrupted.write_text(json.dumps({"schema_version": 1, "repo": "acme/widgets", "pr_number": 999}))
        read = run_helper(["state", "read", "--repo-root", str(repo_root), "--repo", "acme/widgets", "--pr", "42"])
        self.assertNotEqual(read.returncode, 0)
        self.assertEqual(json.loads(read.stdout)["error"]["code"], "STALE_OR_WRONG_STATE")


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
