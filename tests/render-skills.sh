#!/usr/bin/env bash
# tests/render-skills.sh — scripts/render-skills.sh produces valid portable skills.
#
# Checks the Agent Skills constraints the other tools rely on (name equals the
# directory, lowercase 1-64 chars; description 1-1024 chars), that every skill
# was rendered, that no Claude-only "/platform-skills:" reference, userConfig
# placeholder or docs-site key leaked through (frontmatter included), that every references/<file>.md a skill mentions resolves
# inside the rendered skill, that every examples/<path> a skill mentions was
# copied beside it in full (recursively, tracked files only, executable bits
# kept), and that re-rendering leaves foreign skills alone.
#
# Run from the repository root: bash tests/render-skills.sh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT/someone-elses-skill" && echo keep > "$OUT/someone-elses-skill/SKILL.md"

bash scripts/render-skills.sh "$OUT" >/dev/null
bash scripts/render-skills.sh "$OUT" >/dev/null   # idempotent re-render

python3 -I - "$OUT" <<'PY'
import os, re, subprocess, sys
out = sys.argv[1]
errors = []
tracked = set(subprocess.run(["git", "ls-files", "-z", "examples"], check=True,
                             capture_output=True).stdout.decode().split("\0")) - {""}
src = sorted(d for d in os.listdir("skills") if os.path.isfile(f"skills/{d}/SKILL.md"))
want = {("platform-skills" if d == "platform-skills" else f"platform-skills-{d}") for d in src}
got = {d for d in os.listdir(out) if d.startswith("platform-skills")}
if got != want:
    errors.append(f"rendered set differs: missing {sorted(want - got)}, extra {sorted(got - want)}")
if not os.path.isfile(f"{out}/someone-elses-skill/SKILL.md"):
    errors.append("re-render removed a skill it does not own")
for d in sorted(got):
    text = open(f"{out}/{d}/SKILL.md", encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not m:
        errors.append(f"{d}: no frontmatter"); continue
    fm = dict(l.split(":", 1) for l in m.group(1).splitlines() if ":" in l)
    fm = {k.strip(): v.strip().strip('"') for k, v in fm.items()}
    if set(fm) - {"name", "description", "argument-hint"}:
        errors.append(f"{d}: unexpected frontmatter keys {sorted(set(fm) - {'name','description','argument-hint'})}")
    if fm.get("name") != d or not re.fullmatch(r"[a-z0-9-]{1,64}", d):
        errors.append(f"{d}: name {fm.get('name')!r} must equal the directory and be 1-64 lowercase chars")
    if not 1 <= len(fm.get("description", "")) <= 1024:
        errors.append(f"{d}: description must be 1-1024 chars, got {len(fm.get('description',''))}")
    body = m.group(2)
    # The whole file, frontmatter included: a description is what these tools
    # match on, so a Claude-only reference there is as wrong as one in the body.
    if "${user_config." in text:
        errors.append(f"{d}: Claude-only ${{user_config.*}} placeholder left in the skill")
    if re.search(r"\(not configured: [A-Za-z0-9_]+\)", text):
        errors.append(f"{d}: userConfig rendered as a sentinel; skills only recognise an empty value")
    if "/platform-skills:" in text:
        errors.append(f"{d}: Claude-only /platform-skills: reference left in the skill")
    for ref in set(re.findall(r"references/([A-Za-z0-9._-]+\.md)", body)):
        if os.path.isfile(f"references/{ref}") and not os.path.isfile(f"{out}/{d}/references/{ref}"):
            errors.append(f"{d}: mentions references/{ref} but it was not copied beside the skill")
    # Every tracked file under each examples/<path> the skill mentions, recursively.
    for raw in set(re.findall(r"examples/[A-Za-z0-9._/-]+", body)):
        path = raw.rstrip("./")
        files = [f for f in tracked if f == path or f.startswith(path + "/")]
        if not files:
            errors.append(f"{d}: mentions {path} but no tracked file exists there")
        for f in files:
            if not os.path.isfile(f"{out}/{d}/{f}"):
                errors.append(f"{d}: mentions {path} but {f} was not copied beside the skill")
            elif os.access(f, os.X_OK) and not os.access(f"{out}/{d}/{f}", os.X_OK):
                errors.append(f"{d}: {f} lost its executable bit")
    for dirpath, _, names in os.walk(f"{out}/{d}/examples"):
        for n in names:
            rel = os.path.relpath(os.path.join(dirpath, n), f"{out}/{d}")
            if rel not in tracked:
                errors.append(f"{d}: copied {rel}, which is not a tracked file")
for e in errors: print(f"  FAIL: {e}")
print(f"render-skills: {len(got)} skill(s), {len(errors)} error(s)")
sys.exit(1 if errors else 0)
PY
