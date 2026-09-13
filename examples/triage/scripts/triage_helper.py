#!/usr/bin/env python3
"""Deterministic Git/GitHub mechanics for /platform-skills:triage."""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path


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


def run(cmd, cwd=None, check=True, input_text=None):
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, input=input_text)
    if check and proc.returncode != 0:
        raise HelperError(
            "SUBPROCESS_FAILED",
            f"{' '.join(cmd)} failed",
            stdout=proc.stdout, stderr=proc.stderr, returncode=proc.returncode,
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


def _gh_graphql(query, variables, host):
    cmd = ["gh", "api", "graphql", "--hostname", host, "-F", f"query={query}"]
    for key, value in variables.items():
        if value is not None:
            cmd += ["-f", f"{key}={json.dumps(value) if isinstance(value, (dict, list)) else value}"]
    out = run(cmd).stdout
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
            "full_database_id": str(data["full_database_id"]) if data.get("full_database_id") is not None else None,
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
        f"comment {args.comment_id} is not a review comment or an issue comment on this host "
        "(a 404 here can also mean an inaccessible private resource, not proof the ID is wrong)",
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
