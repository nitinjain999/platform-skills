#!/usr/bin/env bash
# tests/plugin-evals-structure.sh — free, model-free checks on plugin-evals/.
#
# Catches the mistakes that otherwise only show up as a failed (and billed)
# `claude plugin eval` run: frontmatter that does not parse, unknown keys, a
# missing or unknown grader type, regex graders that do not compile, a case
# without a grader, a case without a skill-fired check, and a case tag the
# runner's domain map never selects.
#
# Run from the repository root: bash tests/plugin-evals-structure.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 -I - <<'PY'
import glob, json, os, re, sys
errors = []
def fail(msg): errors.append(msg)

def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n?(.*)", text, re.S)
    if not m:
        fail(f"{path}: no YAML frontmatter"); return None, ""
    try:
        import yaml
    except ImportError:
        fail("PyYAML is required (pip install pyyaml)"); return None, ""
    try:
        return yaml.safe_load(m.group(1)) or {}, m.group(2)
    except Exception as e:
        fail(f"{path}: frontmatter does not parse: {e}"); return None, ""

manifest = json.load(open(".claude-plugin/plugin.json"))
eval_dir = manifest.get("experimental", {}).get("evals")
if eval_dir != "plugin-evals":
    fail(f'plugin.json experimental.evals must be "plugin-evals" (evals/ holds the older suite), got {eval_dir!r}')

PROMPT_KEYS = {"schema_version", "name", "description", "tags", "plugins", "runs", "expected_outcome",
               "model", "max_turns", "timeout_seconds", "allowed_tools", "append_system_prompt", "env"}
GRADER_KEYS = {"type", "weight", "arm",
               "pattern", "flags", "match", "target",            # regex
               "tool", "input_match", "min", "max",              # tool_used
               "before", "after", "path", "exists",              # tool_order, file_exists
               "criteria", "focus", "baseline_file"}             # llm, baseline
# The loader's discriminator (claude plugin eval rejects anything else with
# "Invalid discriminator value"); checked here so CI fails before a billed run.
GRADER_TYPES = {"regex", "tool_order", "tool_used", "file_exists", "llm", "baseline"}
runner = open("tests/plugin-evals.sh", encoding="utf-8").read()
mapped_tags = set(re.findall(r"\t([a-z][a-z0-9-]*)\n", runner))

cases = sorted(os.path.dirname(p) for p in glob.glob("plugin-evals/*/prompt.md"))
if not cases:
    fail("no cases under plugin-evals/")
for case in cases:
    fm, body = frontmatter(f"{case}/prompt.md")
    if fm is None: continue
    for k in set(fm) - PROMPT_KEYS:
        fail(f"{case}/prompt.md: unknown frontmatter key {k!r} (claude plugin eval rejects it)")
    if not body.strip():
        fail(f"{case}/prompt.md: empty prompt body")
    tags = set(fm.get("tags") or [])
    if not tags & mapped_tags:
        fail(f"{case}: tags {sorted(tags)} not selected by tests/plugin-evals.sh DOMAIN_MAP {sorted(mapped_tags)}")
    graders = sorted(glob.glob(f"{case}/graders/*.md"))
    if not graders:
        fail(f"{case}: no graders (the case would fail to load)")
    has_skill = False
    for g in graders:
        gfm, _ = frontmatter(g)
        if gfm is None: continue
        for k in set(gfm) - GRADER_KEYS:
            fail(f"{g}: unknown grader key {k!r}")
        t = gfm.get("type")
        if t not in GRADER_TYPES:
            fail(f"{g}: grader type {t!r} is not one of {sorted(GRADER_TYPES)}")
        if t == "regex":
            pat = gfm.get("pattern")
            if not pat:
                fail(f"{g}: regex grader without pattern")
            else:
                if "(?i)" in pat:
                    fail(f"{g}: inline (?i) is not supported; use flags: i")
                try:
                    re.compile(pat)
                except re.error as e:
                    fail(f"{g}: pattern does not compile: {e}")
        if t == "tool_used" and gfm.get("tool") == "Skill":
            has_skill = True
        if gfm.get("weight") is not None and not (isinstance(gfm["weight"], (int, float)) and gfm["weight"] > 0):
            fail(f"{g}: weight must be a positive number")
    if not has_skill:
        fail(f"{case}: no tool_used Skill grader; without it a pass says nothing about the plugin")

base = "plugin-evals/baseline.json"
if os.path.exists(base):
    b = json.load(open(base))
    names = {os.path.basename(c) for c in cases}
    for n in b.get("cases", {}):
        if n not in names:
            fail(f"{base}: baseline for {n!r} but no such case")

for e in errors:
    print(f"  FAIL: {e}")
print(f"plugin-evals structure: {len(cases)} case(s), {len(errors)} error(s)")
sys.exit(1 if errors else 0)
PY
