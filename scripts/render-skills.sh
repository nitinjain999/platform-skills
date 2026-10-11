#!/usr/bin/env bash
# scripts/render-skills.sh — render skills/ as portable Agent Skills for tools
# that are not the Claude plugin: GitHub Copilot (VS Code), Cursor, and Codex
# all read <dir>/<name>/SKILL.md, for example from a project's .agents/skills/.
#
# The Claude plugin namespaces its skills (/platform-skills:<name>); these tools
# do not, so a skill named "debug" or "commit" would collide with the user's own.
# Each rendered skill is therefore renamed platform-skills-<name> (the router
# keeps "platform-skills"), and:
#   - frontmatter keeps only the Agent Skills fields (name, description,
#     with any when_to_use appended to it,
#     argument-hint); the docs-site keys (title, sidebar_label, custom_edit_url)
#     are dropped
#   - "/platform-skills:<name>" cross-references become "/platform-skills-<name>"
#   - every references/<file>.md a skill mentions is copied into that skill's
#     own references/ directory, so the relative path in the text resolves
#
# Usage: bash scripts/render-skills.sh <destination-skills-dir>
# The destination's existing platform-skills* directories are replaced; any
# other skills in it are left alone.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?usage: render-skills.sh <destination-skills-dir>}"
mkdir -p "$DEST"

python3 -I - "$ROOT_DIR" "$DEST" <<'PY'
import os, re, shutil, sys
root, dest = sys.argv[1], sys.argv[2]
PREFIX = "platform-skills"
KEEP = ("name", "description", "argument-hint")

def target_name(name):
    return PREFIX if name == PREFIX else f"{PREFIX}-{name}"

skills = sorted(d for d in os.listdir(f"{root}/skills") if os.path.isfile(f"{root}/skills/{d}/SKILL.md"))
for d in os.listdir(dest):
    if d == PREFIX or d.startswith(PREFIX + "-"):
        shutil.rmtree(os.path.join(dest, d))

for name in skills:
    text = open(f"{root}/skills/{name}/SKILL.md", encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not m:
        sys.exit(f"skills/{name}/SKILL.md: no frontmatter")
    fm_lines, body = m.group(1).splitlines(), m.group(2)
    # when_to_use is Claude-only; fold it into description so other tools still
    # see the trigger phrases (Agent Skills caps description at 1024 chars).
    when = next((l.split(":", 1)[1].strip() for l in fm_lines if l.split(":", 1)[0].strip() == "when_to_use"), "")
    kept = []
    for line in fm_lines:
        key = line.split(":", 1)[0].strip()
        if key == "name":
            kept.append(f"name: {target_name(name)}")
        elif key == "description" and when:
            desc = f"{line.split(':', 1)[1].strip()} {when}"
            if len(desc) > 1024:
                sys.exit(f"skills/{name}/SKILL.md: description + when_to_use is {len(desc)} chars; portable skills allow 1024")
            kept.append(f"description: {desc}")
        elif key in KEEP:
            kept.append(line)
    body = re.sub(r"/platform-skills:([a-z0-9-]+)", lambda mm: f"/{target_name(mm.group(1))}", body)
    out_dir = os.path.join(dest, target_name(name))
    os.makedirs(out_dir)
    with open(os.path.join(out_dir, "SKILL.md"), "w", encoding="utf-8") as f:
        f.write("---\n" + "\n".join(kept) + "\n---\n" + body)
    for ref in sorted(set(re.findall(r"references/([A-Za-z0-9._-]+\.md)", body))):
        src = f"{root}/references/{ref}"
        if os.path.isfile(src):
            os.makedirs(os.path.join(out_dir, "references"), exist_ok=True)
            shutil.copyfile(src, os.path.join(out_dir, "references", ref))
print(f"rendered {len(skills)} skills into {dest}")
PY
