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


def build_parser():
    parser = argparse.ArgumentParser(prog="triage_helper.py")
    parser.add_subparsers(dest="command", required=True)
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
    except Exception as e:  # last resort: never surface a raw traceback
        emit_error("UNEXPECTED_ERROR", str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
