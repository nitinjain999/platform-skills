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
#   - "/platform-skills:<name>" cross-references become "/platform-skills-<name>",
#     in the description as well as the body
#   - ${user_config.KEY} placeholders (Claude plugin only) become empty, which
#     is what each skill already treats as "not configured, ask the user"
#   - every references/<file>.md a skill mentions is copied into that skill's
#     own references/ directory, so the relative path in the text resolves
#   - every examples/<path> a skill mentions (a file, or a directory copied
#     recursively) is copied into that skill's own examples/ directory, for the
#     same reason: scripts, manifests and workflows the skill tells the agent
#     to run or start from. Only files tracked by git are copied (local
#     .terraform caches, state and tfvars stay behind); outside a git checkout
#     those are skipped by name instead
#   - each skill's own scripts/ directory is copied beside SKILL.md, with the
#     same tracked-file filtering and executable-bit preservation
#
# Usage: bash scripts/render-skills.sh <destination-skills-dir>
# The destination's existing platform-skills* directories are replaced; any
# other skills in it are left alone.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?usage: render-skills.sh <destination-skills-dir>}"
mkdir -p "$DEST"

python3 -I - "$ROOT_DIR" "$DEST" <<'PY'
import fnmatch, os, re, shutil, subprocess, sys
root, dest = sys.argv[1], sys.argv[2]
PREFIX = "platform-skills"
KEEP = ("name", "description", "argument-hint")
EXAMPLE_PATH = re.compile(r"examples/[A-Za-z0-9._/-]+")

def tracked_files(prefix):
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-z", "--", prefix],
                             check=True, capture_output=True).stdout.decode()
        files = [f for f in out.split("\0") if f and os.path.isfile(os.path.join(root, f))]
        return files
    except (OSError, subprocess.CalledProcessError):
        pass
    # Not a git checkout: exclude build caches and local Terraform inputs.
    skip_dirs = {".terraform", ".git", "node_modules", "__pycache__", ".venv"}
    skip_files = (".terraform.lock.hcl", "*.tfstate", "*.tfstate.*", "*.tfvars", "*.tfvars.json", "*.pyc")
    files = []
    for d, dirs, names in os.walk(os.path.join(root, prefix)):
        dirs[:] = [x for x in dirs if x not in skip_dirs]
        files += [os.path.relpath(os.path.join(d, n), root) for n in names
                  if not any(fnmatch.fnmatch(n, p) for p in skip_files)]
    return files

EXAMPLES = sorted(tracked_files("examples"))

def examples_for(body):
    """Tracked files under every examples/<path> the body mentions."""
    picked = set()
    for raw in set(EXAMPLE_PATH.findall(body)):
        path = raw.rstrip("./")
        picked.update(f for f in EXAMPLES if f == path or f.startswith(path + "/"))
    return sorted(picked)

def target_name(name):
    return PREFIX if name == PREFIX else f"{PREFIX}-{name}"

skills = sorted(d for d in os.listdir(f"{root}/skills") if os.path.isfile(f"{root}/skills/{d}/SKILL.md"))
for d in os.listdir(dest):
    if d == PREFIX or d.startswith(PREFIX + "-"):
        shutil.rmtree(os.path.join(dest, d))

def portable(text):
    # Applied to the whole file, frontmatter included: descriptions name other
    # skills too, and that text is what these tools match on.
    text = re.sub(r"/platform-skills:([a-z0-9-]+)", lambda mm: f"/{target_name(mm.group(1))}", text)
    # userConfig values are substituted by the Claude plugin only. Render them
    # empty: every skill that reads one treats an empty value as not configured.
    return re.sub(r"\$\{user_config\.[A-Za-z0-9_]+\}", "", text)

for name in skills:
    text = portable(open(f"{root}/skills/{name}/SKILL.md", encoding="utf-8").read())
    m = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not m:
        sys.exit(f"skills/{name}/SKILL.md: no frontmatter")
    fm_lines, body = m.group(1).splitlines(), m.group(2)
    # when_to_use is Claude-only; fold it into description so other tools still
    # see the trigger phrases (Agent Skills caps description at 1024 chars).
    when = next((l.split(":", 1)[1].strip() for l in fm_lines if l.split(":", 1)[0].strip() == "when_to_use"), "")
    kept = []
    for line in fm_lines:
        field = line.split(":", 1)[0].strip()
        if field == "name":
            kept.append(f"name: {target_name(name)}")
        elif field == "description" and when:
            desc = f"{line.split(':', 1)[1].strip()} {when}"
            if len(desc) > 1024:
                sys.exit(f"skills/{name}/SKILL.md: description + when_to_use is {len(desc)} chars; portable skills allow 1024")
            kept.append(f"description: {desc}")
        elif field in KEEP:
            kept.append(line)
    out_dir = os.path.join(dest, target_name(name))
    os.makedirs(out_dir)
    with open(os.path.join(out_dir, "SKILL.md"), "w", encoding="utf-8") as f:
        f.write("---\n" + "\n".join(kept) + "\n---\n" + body)
    for ref in sorted(set(re.findall(r"references/([A-Za-z0-9._-]+\.md)", body))):
        src = f"{root}/references/{ref}"
        if os.path.isfile(src):
            os.makedirs(os.path.join(out_dir, "references"), exist_ok=True)
            shutil.copyfile(src, os.path.join(out_dir, "references", ref))
    for rel in examples_for(body):
        target = os.path.join(out_dir, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(f"{root}/{rel}", target)   # copy2 keeps the executable bit on scripts
    for rel in tracked_files(f"skills/{name}/scripts"):
        target = os.path.join(out_dir, os.path.relpath(rel, f"skills/{name}"))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(root, rel), target)
print(f"rendered {len(skills)} skills into {dest}")
PY
