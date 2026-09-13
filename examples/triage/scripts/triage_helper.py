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


class HelperError(Exception):
    def __init__(self, code, message, **extra):
        super().__init__(message)
        self.code = code
        self.message = message
        self.extra = extra


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


def build_parser():
    parser = argparse.ArgumentParser(prog="triage_helper.py")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("resolve-identity")
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--host")
    p.set_defaults(func=cmd_resolve_identity)

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
