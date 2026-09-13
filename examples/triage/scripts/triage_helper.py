#!/usr/bin/env python3
"""Deterministic Git/GitHub mechanics for /platform-skills:triage."""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

STATE_DIR_NAME = "triage-state"
SCHEMA_VERSION = 1
URL_USERINFO_RE = re.compile(r"://[^@/\s]*@")


GRAPHQL_THREADS_PAGE = """
query($owner:String!, $repo:String!, $pr:Int!, $after:String) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:50, after:$after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated viewerCanReply viewerCanResolve
          comments(first:50) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id databaseId fullDatabaseId body path line
              author { login } updatedAt replyTo { id }
            }
          }
        }
      }
    }
  }
}
"""

GRAPHQL_THREAD_COMMENTS_PAGE = """
query($threadId:ID!, $after:String) {
  node(id:$threadId) {
    ... on PullRequestReviewThread {
      comments(first:50, after:$after) {
        pageInfo { hasNextPage endCursor }
        nodes { id databaseId fullDatabaseId body path line author { login } updatedAt replyTo { id } }
      }
    }
  }
}
"""


class HelperError(Exception):
    def __init__(self, code, message, **extra):
        super().__init__(message)
        self.code = code
        self.message = message
        self.extra = extra


class JSONArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        emit_error("ARGUMENT_ERROR", message)
        self.exit(2)


def redact(text):
    if not isinstance(text, str):
        return text
    return URL_USERINFO_RE.sub("://", text)


def run(cmd, cwd=None, check=True, input_text=None):
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, input=input_text)
    if check and proc.returncode != 0:
        raise HelperError(
            "SUBPROCESS_FAILED",
            redact(f"{' '.join(cmd)} failed"),
            stdout=redact(proc.stdout), stderr=redact(proc.stderr), returncode=proc.returncode,
        )
    return proc


def emit(obj):
    print(json.dumps(obj, indent=2))


def emit_error(code, message, **extra):
    emit({"ok": False, "error": {"code": code, "message": message, **extra}})


def cmd_resolve_identity(args):
    host = args.host or "github.com"
    out = run(["gh", "api", f"repos/{args.repo}/pulls/{args.pr}", "--hostname", host]).stdout
    pr_data = json.loads(out)

    if pr_data.get("state") != "open":
        raise HelperError("PR_NOT_OPEN", f"PR #{args.pr} is not open (state={pr_data.get('state')})")

    base_repo = pr_data["base"]["repo"]["full_name"]
    head_repo_data = pr_data["head"].get("repo")
    head_repo = head_repo_data["full_name"] if head_repo_data else None
    is_fork = head_repo is not None and head_repo != base_repo

    emit({
        "ok": True,
        "repo": args.repo,
        "host": host,
        "pr_number": args.pr,
        "state": pr_data["state"],
        "is_draft": pr_data.get("draft", False),
        "base_repo": base_repo,
        "head_repo": head_repo,
        "head_ref": pr_data["head"]["ref"],
        "head_sha": pr_data["head"]["sha"],
        "is_fork": is_fork,
    })


def _graphql_payload_file(query, variables):
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump({"query": query, "variables": variables}, f)
    return path


def _gh_graphql(query, variables, host):
    payload_path = _graphql_payload_file(query, variables)
    try:
        out = run(["gh", "api", "graphql", "--hostname", host, "--input", payload_path]).stdout
    finally:
        os.unlink(payload_path)
    data = json.loads(out)
    if data.get("errors"):
        raise HelperError("GRAPHQL_ERROR", "GraphQL query returned errors", errors=data["errors"])
    return data


def _normalize_comment(c):
    return {
        "node_id": c["id"],
        "database_id": str(c["databaseId"]) if c.get("databaseId") is not None else None,
        "full_database_id": str(c["fullDatabaseId"]) if c.get("fullDatabaseId") is not None else None,
        "body": c["body"],
        "path": c.get("path"),
        "line": c.get("line"),
        "author": (c.get("author") or {}).get("login"),
        "updated_at": c.get("updatedAt"),
        "reply_to_node_id": (c.get("replyTo") or {}).get("id"),
    }


def _paginate_thread_comments(thread, host):
    nodes = [_normalize_comment(c) for c in thread["comments"]["nodes"]]
    page_info = thread["comments"]["pageInfo"]
    while page_info["hasNextPage"]:
        data = _gh_graphql(GRAPHQL_THREAD_COMMENTS_PAGE, {"threadId": thread["id"], "after": page_info["endCursor"]}, host)
        page = data["data"]["node"]["comments"]
        nodes += [_normalize_comment(c) for c in page["nodes"]]
        page_info = page["pageInfo"]
    return nodes


def _paginate_threads(owner, repo, pr, host):
    threads = []
    after = None
    while True:
        variables = {"owner": owner, "repo": repo, "pr": pr}
        if after is not None:
            variables["after"] = after
        data = _gh_graphql(GRAPHQL_THREADS_PAGE, variables, host)
        page = data["data"]["repository"]["pullRequest"]["reviewThreads"]
        for thread in page["nodes"]:
            threads.append({
                "id": thread["id"],
                "is_resolved": thread["isResolved"],
                "is_outdated": thread.get("isOutdated", False),
                "viewer_can_reply": thread.get("viewerCanReply", False),
                "viewer_can_resolve": thread.get("viewerCanResolve", False),
                "comments": _paginate_thread_comments(thread, host),
            })
        if not page["pageInfo"]["hasNextPage"]:
            break
        after = page["pageInfo"]["endCursor"]
    return threads


def _head_sha(repo, pr, host):
    out = run(["gh", "api", f"repos/{repo}/pulls/{pr}", "--hostname", host]).stdout
    return json.loads(out)["head"]["sha"]


def cmd_resolve_comment(args):
    host = args.host or "github.com"

    review = run(["gh", "api", f"repos/{args.repo}/pulls/comments/{args.comment_id}", "--hostname", host], check=False)
    if review.returncode == 0:
        data = json.loads(review.stdout)
        pr_url = data.get("pull_request_url", "")
        belongs = pr_url.rstrip("/").endswith(f"/pulls/{args.pr}")
        if not belongs:
            raise HelperError(
                "COMMENT_WRONG_PR",
                f"comment {args.comment_id} belongs to a different PR than #{args.pr}",
                pull_request_url=pr_url,
            )
        emit({
            "ok": True,
            "comment_type": "review",
            "node_id": data["node_id"],
            "database_id": str(data["id"]),
            "full_database_id": None,
            "belongs_to_pr": True,
            "pull_request_url": pr_url,
        })
        return

    issue = run(["gh", "api", f"repos/{args.repo}/issues/comments/{args.comment_id}", "--hostname", host], check=False)
    if issue.returncode == 0:
        data = json.loads(issue.stdout)
        html_url = data.get("html_url", "")
        belongs = f"/pull/{args.pr}#" in html_url
        if not belongs:
            raise HelperError(
                "COMMENT_WRONG_PR",
                f"comment {args.comment_id} belongs to a different PR than #{args.pr}",
                html_url=html_url,
            )
        emit({
            "ok": True,
            "comment_type": "issue",
            "node_id": data["node_id"],
            "database_id": str(data["id"]),
            "full_database_id": None,
            "belongs_to_pr": True,
            "pull_request_url": None,
        })
        return

    raise HelperError(
        "COMMENT_NOT_FOUND",
        f"comment {args.comment_id} was not returned as a review comment or an issue comment on this host "
        "(a 404 here can also mean an inaccessible private resource, and a non-404 transport or auth failure "
        "is reported below rather than proving the ID is wrong)",
        review_lookup_returncode=review.returncode,
        review_lookup_stderr=redact(review.stderr),
        issue_lookup_returncode=issue.returncode,
        issue_lookup_stderr=redact(issue.stderr),
    )


def cmd_snapshot(args):
    host = args.host or "github.com"
    owner, repo = args.repo.split("/", 1)

    head_before = _head_sha(args.repo, args.pr, host)
    threads = _paginate_threads(owner, repo, args.pr, host)
    head_after = _head_sha(args.repo, args.pr, host)

    snapshot = {
        "ok": True,
        "repo": args.repo,
        "pr_number": args.pr,
        "head_sha_before": head_before,
        "head_sha_after": head_after,
        "head_changed_during_collection": head_before != head_after,
        "threads": threads,
    }
    if args.out:
        Path(args.out).write_text(json.dumps(snapshot, indent=2))
    emit(snapshot)


def cmd_map_thread(args):
    snapshot = json.loads(Path(args.snapshot).read_text())
    comment_id = str(args.comment_id)
    for thread in snapshot["threads"]:
        for idx, c in enumerate(thread["comments"]):
            if comment_id in (c["database_id"], c["full_database_id"], c["node_id"]):
                emit({
                    "ok": True,
                    "thread_node_id": thread["id"],
                    "is_resolved": thread["is_resolved"],
                    "viewer_can_reply": thread["viewer_can_reply"],
                    "viewer_can_resolve": thread["viewer_can_resolve"],
                    "matched_comment_node_id": c["node_id"],
                    "is_root_comment": idx == 0,
                })
                return
    raise HelperError("COMMENT_NOT_IN_SNAPSHOT", f"comment {args.comment_id} not found in any collected thread")


def cmd_patch_context(args):
    host = args.host or "github.com"
    out = run(["gh", "api", f"repos/{args.repo}/pulls/{args.pr}/files", "--hostname", host, "--paginate"]).stdout
    entries = json.loads(out)

    match = None
    for e in entries:
        if e["filename"] == args.path or e.get("previous_filename") == args.path:
            match = e
            break

    if match is None:
        emit({"ok": True, "evidence_status": "NOT_IN_DIFF", "filename": None, "previous_filename": None, "patch": None})
        return

    if match.get("patch"):
        emit({
            "ok": True,
            "evidence_status": "RENAMED" if match.get("previous_filename") else "PATCH_OK",
            "filename": match["filename"],
            "previous_filename": match.get("previous_filename"),
            "patch": match["patch"],
        })
        return

    if args.base_sha and args.head_sha and args.repo_root:
        diff = run(["git", "diff", f"{args.base_sha}..{args.head_sha}", "--", match["filename"]], cwd=args.repo_root, check=False)
        if diff.returncode == 0 and diff.stdout.strip():
            emit({
                "ok": True, "evidence_status": "LOCAL_DIFF_FALLBACK",
                "filename": match["filename"], "previous_filename": match.get("previous_filename"),
                "patch": diff.stdout,
            })
            return

    emit({
        "ok": True, "evidence_status": "BINARY_OR_UNAVAILABLE",
        "filename": match["filename"], "previous_filename": match.get("previous_filename"), "patch": None,
    })


def cmd_worktree_prepare(args):
    worktree_dir = tempfile.mkdtemp(prefix="triage-worktree-")
    run(["git", "worktree", "add", "--detach", worktree_dir, args.head_sha], cwd=args.repo_root)
    emit({"ok": True, "worktree_path": worktree_dir, "head_sha": args.head_sha})


def cmd_worktree_cleanup(args):
    run(["git", "worktree", "remove", "--force", args.path], cwd=args.repo_root)
    emit({"ok": True, "removed": args.path})


def cmd_stage_commit(args):
    run(["git", "add", "--"] + args.paths, cwd=args.worktree)
    staged_raw = run(["git", "diff", "--cached", "--name-only", "-z"], cwd=args.worktree).stdout
    staged = [p for p in staged_raw.split("\0") if p]
    staged_set, intended_set = set(staged), set(args.paths)
    if staged_set != intended_set:
        raise HelperError(
            "STAGED_SET_MISMATCH",
            "staged files do not match the intended path allowlist",
            staged=sorted(staged_set), intended=sorted(intended_set),
        )
    run(["git", "commit", "-m", args.message], cwd=args.worktree)
    sha = run(["git", "rev-parse", "HEAD"], cwd=args.worktree).stdout.strip()
    emit({"ok": True, "commit_sha": sha, "committed_paths": sorted(staged_set)})


def cmd_publish(args):
    host = args.host or "github.com"
    current = json.loads(run(["gh", "api", f"repos/{args.repo}/pulls/{args.pr}", "--hostname", host]).stdout)["head"]["sha"]

    if current != args.expected_head_sha:
        raise HelperError(
            "HEAD_MOVED",
            "PR head advanced since the plan was built; refresh and revalidate before retrying",
            expected=args.expected_head_sha, actual=current,
        )

    refspec = f"{args.commit_sha}:refs/heads/{args.head_ref}"
    push = run(["git", "push", args.head_remote_url, refspec], cwd=args.worktree, check=False)
    if push.returncode != 0:
        stderr = redact(push.stderr)
        lowered = stderr.lower()
        if "protected branch" in lowered or "hook declined" in lowered:
            raise HelperError(
                "PUSH_REJECTED_BY_POLICY",
                "the head repository refused the push by policy (branch protection or a server-side hook); "
                "this is not a non-fast-forward and retrying after a refresh will not clear it",
                stderr=stderr,
            )
        if "permission" in lowered or "403" in stderr or "authentication failed" in lowered:
            raise HelperError("NO_PUSH_PERMISSION", "no write access to the head repository", stderr=stderr)
        if "non-fast-forward" in lowered or "fetch first" in lowered or "rejected" in lowered:
            raise HelperError("PUSH_REJECTED_NON_FASTFORWARD", "remote head moved; refresh before retrying", stderr=stderr)
        raise HelperError("UNKNOWN_TRANSPORT_FAILURE", "push failed for an unrecognized reason", stderr=stderr)

    after = run(["git", "ls-remote", args.head_remote_url, f"refs/heads/{args.head_ref}"], cwd=args.worktree).stdout.split()[0]
    emit({
        "ok": True, "pushed_commit": args.commit_sha, "remote_head_after": after,
        "matches_pushed_commit": after == args.commit_sha,
    })


def _thread_already_has_marker(snapshot_path, thread_node_id, marker):
    if not snapshot_path or not marker:
        return False
    snapshot = json.loads(Path(snapshot_path).read_text())
    for thread in snapshot["threads"]:
        if thread["id"] == thread_node_id:
            return any(marker in (c.get("body") or "") for c in thread["comments"])
    return False


def cmd_reply(args):
    host = args.host or "github.com"

    if not args.thread_node_id and args.pr is None:
        raise HelperError(
            "INVALID_ARGUMENTS",
            "reply needs either --thread-node-id (review thread reply) or --pr (PR conversation comment)",
        )
    if not args.thread_node_id and (args.dedup_marker or args.snapshot):
        raise HelperError(
            "INVALID_ARGUMENTS",
            "--dedup-marker/--snapshot are only checked on the --thread-node-id path; "
            "the PR conversation comment path has no dedup mechanism, so passing them there would be misleading",
        )

    body = Path(args.body_file).read_text()

    if args.thread_node_id:
        if _thread_already_has_marker(args.snapshot, args.thread_node_id, args.dedup_marker):
            emit({"ok": True, "status": "ALREADY_REPLIED", "thread_node_id": args.thread_node_id})
            return

        query = """
        mutation($threadId: ID!, $body: String!) {
          addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
            comment { id url }
          }
        }
        """
        payload_path = _graphql_payload_file(query, {"threadId": args.thread_node_id, "body": body})
        try:
            result = run(["gh", "api", "graphql", "--hostname", host, "--input", payload_path])
        finally:
            os.unlink(payload_path)
        data = json.loads(result.stdout)
        if data.get("errors"):
            raise HelperError("REPLY_FAILED", "addPullRequestReviewThreadReply failed", errors=data["errors"])
        comment = data["data"]["addPullRequestReviewThreadReply"]["comment"]
        emit({"ok": True, "status": "CONFIRMED", "comment_node_id": comment["id"], "comment_id": None, "url": comment["url"]})
        return

    fd, payload_path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump({"body": body}, f)
    try:
        result = run(["gh", "api", f"repos/{args.repo}/issues/{args.pr}/comments", "--hostname", host, "--input", payload_path], check=False)
    finally:
        os.unlink(payload_path)
    if result.returncode != 0:
        raise HelperError("REPLY_UNKNOWN", "conversation comment POST failed or response ambiguous", stderr=result.stderr, returncode=result.returncode)
    data = json.loads(result.stdout)
    emit({"ok": True, "status": "CONFIRMED", "comment_node_id": None, "comment_id": str(data["id"]), "url": data["html_url"]})


def cmd_resolve_thread(args):
    host = args.host or "github.com"

    check_query = """
    query($id: ID!) {
      node(id: $id) { ... on PullRequestReviewThread { isResolved viewerCanResolve } }
    }
    """
    payload_path = _graphql_payload_file(check_query, {"id": args.thread_node_id})
    try:
        pre = json.loads(run(["gh", "api", "graphql", "--hostname", host, "--input", payload_path]).stdout)
    finally:
        os.unlink(payload_path)
    node = pre["data"]["node"]

    if node["isResolved"]:
        emit({"ok": True, "status": "ALREADY_RESOLVED", "thread_node_id": args.thread_node_id})
        return
    if not node["viewerCanResolve"]:
        raise HelperError("NOT_AUTHORIZED", "viewerCanResolve is false for this thread")

    mutation = """
    mutation($id: ID!) {
      resolveReviewThread(input: {threadId: $id}) { thread { isResolved } }
    }
    """
    payload_path = _graphql_payload_file(mutation, {"id": args.thread_node_id})
    try:
        result = json.loads(run(["gh", "api", "graphql", "--hostname", host, "--input", payload_path]).stdout)
    finally:
        os.unlink(payload_path)

    if result.get("errors"):
        raise HelperError("RESOLVE_FAILED", "resolveReviewThread returned errors", errors=result["errors"])
    resolved = result["data"]["resolveReviewThread"]["thread"]["isResolved"]
    if not resolved:
        raise HelperError("RESOLVE_NOT_CONFIRMED", "mutation returned isResolved=false")
    emit({"ok": True, "status": "CONFIRMED", "thread_node_id": args.thread_node_id})


def _state_dir(repo_root):
    git_path = Path(repo_root) / ".git"
    if git_path.is_file():
        raise HelperError(
            "REPO_ROOT_IS_LINKED_WORKTREE",
            f"{git_path} is a file, not a directory, so --repo-root points at a linked worktree; "
            "pass the main checkout's root (the one whose .git is a directory) instead",
            repo_root=str(repo_root), git_path=str(git_path),
        )
    d = git_path / STATE_DIR_NAME
    d.mkdir(parents=True, exist_ok=True)
    return d


def _safe_name(repo, pr):
    return f"{repo.replace('/', '__')}-{pr}"


def _state_file(repo_root, repo, pr):
    return _state_dir(repo_root) / f"{_safe_name(repo, pr)}.json"


def _lock_file(repo_root, repo, pr):
    return _state_dir(repo_root) / f"{_safe_name(repo, pr)}.lock"


def _read_lock_holder(lock_path):
    try:
        held = json.loads(Path(lock_path).read_text())
    except (OSError, ValueError):
        return None, None
    if not isinstance(held, dict):
        return None, None
    return held.get("pid"), held.get("acquired_at")


def cmd_state_lock(args):
    lock_path = _lock_file(args.repo_root, args.repo, args.pr)
    try:
        fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.write(fd, json.dumps({"pid": os.getpid(), "acquired_at": time.time()}).encode())
        os.close(fd)
        emit({"ok": True, "status": "ACQUIRED", "lock_path": str(lock_path)})
    except FileExistsError:
        held_by_pid, held_since = _read_lock_holder(lock_path)
        raise HelperError(
            "LOCK_HELD",
            "another triage instance holds the lock for this repo/PR; if that process is gone, "
            "release it with `state unlock --force-unlock` after confirming held_by_pid is not running",
            lock_path=str(lock_path), held_by_pid=held_by_pid, held_since=held_since,
        )


def cmd_state_unlock(args):
    lock_path = _lock_file(args.repo_root, args.repo, args.pr)
    if not lock_path.exists():
        emit({"ok": True, "status": "RELEASED", "existed": False, "held_by_pid": None, "held_since": None})
        return

    held_by_pid, held_since = _read_lock_holder(lock_path)
    if held_by_pid is None and not args.force_unlock:
        raise HelperError(
            "LOCK_NOT_RECOGNIZED",
            "the lock file is unreadable or was not written by this helper, so it is not safe to assume "
            "it belongs to this run; re-run with --force-unlock once the holding process is confirmed dead",
            lock_path=str(lock_path),
        )

    lock_path.unlink(missing_ok=True)
    emit({
        "ok": True, "status": "RELEASED", "existed": True,
        "forced": bool(args.force_unlock), "held_by_pid": held_by_pid, "held_since": held_since,
    })


def cmd_state_read(args):
    path = _state_file(args.repo_root, args.repo, args.pr)
    if not path.exists():
        emit({"ok": True, "exists": False})
        return
    record = json.loads(path.read_text())
    if record.get("schema_version") != SCHEMA_VERSION or record.get("repo") != args.repo or record.get("pr_number") != args.pr:
        raise HelperError(
            "STALE_OR_WRONG_STATE",
            "state record fails identity/schema check; refusing to reuse",
            record_repo=record.get("repo"), record_pr=record.get("pr_number"), record_schema=record.get("schema_version"),
        )
    emit({"ok": True, "exists": True, "record": record})


def cmd_state_write(args):
    path = _state_file(args.repo_root, args.repo, args.pr)
    record = json.loads(Path(args.record_file).read_text())
    record["schema_version"] = SCHEMA_VERSION
    record["repo"] = args.repo
    record["pr_number"] = args.pr
    record["updated_at"] = time.time()
    path.write_text(json.dumps(record, indent=2))
    emit({"ok": True, "status": "WRITTEN", "path": str(path)})


def build_parser():
    parser = JSONArgumentParser(prog="triage_helper.py")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("resolve-identity")
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--host")
    p.set_defaults(func=cmd_resolve_identity)

    p = sub.add_parser("resolve-comment")
    p.add_argument("--repo", required=True)
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--comment-id", required=True)
    p.add_argument("--host")
    p.set_defaults(func=cmd_resolve_comment)

    p = sub.add_parser("snapshot")
    p.add_argument("--repo", required=True)
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--host")
    p.add_argument("--out")
    p.set_defaults(func=cmd_snapshot)

    p = sub.add_parser("map-thread")
    p.add_argument("--snapshot", required=True)
    p.add_argument("--comment-id", required=True)
    p.set_defaults(func=cmd_map_thread)

    p = sub.add_parser("patch-context")
    p.add_argument("--repo", required=True)
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--path", required=True)
    p.add_argument("--base-sha")
    p.add_argument("--head-sha")
    p.add_argument("--repo-root")
    p.add_argument("--host")
    p.set_defaults(func=cmd_patch_context)

    p = sub.add_parser("stage-commit")
    p.add_argument("--worktree", required=True)
    p.add_argument("--paths", nargs="+", required=True)
    p.add_argument("--message", required=True)
    p.set_defaults(func=cmd_stage_commit)

    p = sub.add_parser("worktree")
    wsub = p.add_subparsers(dest="worktree_command", required=True)

    wp = wsub.add_parser("prepare")
    wp.add_argument("--repo-root", required=True)
    wp.add_argument("--head-sha", required=True)
    wp.set_defaults(func=cmd_worktree_prepare)

    wc = wsub.add_parser("cleanup")
    wc.add_argument("--repo-root", required=True)
    wc.add_argument("--path", required=True)
    wc.set_defaults(func=cmd_worktree_cleanup)

    p = sub.add_parser("publish")
    p.add_argument("--repo", required=True)
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--worktree", required=True)
    p.add_argument("--expected-head-sha", required=True)
    p.add_argument("--commit-sha", required=True)
    p.add_argument("--head-remote-url", required=True)
    p.add_argument("--head-ref", required=True)
    p.add_argument("--host")
    p.set_defaults(func=cmd_publish)

    p = sub.add_parser("reply")
    p.add_argument("--repo", required=True)
    p.add_argument("--pr", type=int)
    p.add_argument("--thread-node-id")
    p.add_argument("--body-file", required=True)
    p.add_argument("--snapshot")
    p.add_argument("--dedup-marker")
    p.add_argument("--host")
    p.set_defaults(func=cmd_reply)

    p = sub.add_parser("resolve-thread")
    p.add_argument("--thread-node-id", required=True)
    p.add_argument("--host")
    p.set_defaults(func=cmd_resolve_thread)

    p = sub.add_parser("state")
    ssub = p.add_subparsers(dest="state_command", required=True)
    for name, func in (
        ("lock", cmd_state_lock), ("unlock", cmd_state_unlock),
        ("read", cmd_state_read), ("write", cmd_state_write),
    ):
        sp = ssub.add_parser(name)
        sp.add_argument("--repo-root", required=True)
        sp.add_argument("--repo", required=True)
        sp.add_argument("--pr", type=int, required=True)
        if name == "write":
            sp.add_argument("--record-file", required=True)
        if name == "unlock":
            sp.add_argument("--force-unlock", action="store_true")
        sp.set_defaults(func=func)

    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
        return 0
    except HelperError as e:
        emit_error(e.code, e.message, **e.extra)
        return 1
    except Exception as e:
        emit_error("UNEXPECTED_ERROR", str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
