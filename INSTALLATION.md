# Installation Guide

This is the canonical install reference for platform-skills.

**No installation needed to use the handbook.** Browse [references/](references/) and [examples/](examples/) directly on GitHub.
Install only if you want agent-assisted guidance in Claude, Codex, or an editor.

---

## Fast path — local installer

Clone once and install the integrations you want:

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
./install.sh --all --target /path/to/your-project
```

Common variants:

```bash
./install.sh --codex
./install.sh --cursor --target /path/to/your-project
./install.sh --copilot --target /path/to/your-project
./install.sh --claude
```

The installer links the local clone for Codex, copies Cursor and Copilot files into the target project, and installs the Claude plugin when the `claude` CLI is available. Existing target files are backed up with a `.bak` suffix before they are replaced.

---

## Option A — GitHub Copilot (no Claude required)

Works in VSCode, JetBrains, Cursor, and any editor with Copilot support.

```bash
# Clone platform-skills
git clone https://github.com/nitinjain999/platform-skills.git

# Create .github directory in your project (if it doesn't exist)
mkdir -p your-project/.github                                           # macOS / Linux
# New-Item -ItemType Directory -Force your-project\.github             # Windows PowerShell

# Copy the instructions file into your project
# macOS / Linux
cp platform-skills/.github/copilot-instructions.md your-project/.github/copilot-instructions.md

# Windows (PowerShell)
Copy-Item platform-skills\.github\copilot-instructions.md your-project\.github\copilot-instructions.md

# Commit — every team member gets it automatically
cd your-project
git add .github/copilot-instructions.md
git commit -m "chore: add platform-skills copilot instructions"
git push
```

Open Copilot Chat and ask platform engineering questions — the rules are active.

**Upgrade:**

```bash
cd platform-skills && git pull origin main
cp .github/copilot-instructions.md your-project/.github/copilot-instructions.md
cd your-project && git add .github/copilot-instructions.md && git commit -m "chore: update platform-skills copilot instructions"
```

→ For global (all-projects) setup and Cursor rules: [EDITOR_INTEGRATIONS.md](EDITOR_INTEGRATIONS.md)

---

## Option B — Codex skill from GitHub

Codex discovers local skills from `${CODEX_HOME:-$HOME/.codex}/skills`. Clone this repository as the skill folder so the root `SKILL.md`, `agents/openai.yaml`, `references/`, and `examples/` remain together:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
git clone https://github.com/nitinjain999/platform-skills.git "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills"
```

**Verify:**

```bash
test -f "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills/SKILL.md"
test -f "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills/agents/openai.yaml"
```

Open Codex in your project and ask:

```text
Use $platform-skills to review this Kubernetes manifest for production readiness.
```

**Upgrade:**

```bash
cd "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills"
git pull --ff-only
```

**Local development symlink:**

Use this when you are editing this repository and want Codex to use your working tree:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -sfn "$PWD" "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills"
```

---

## Option C — Cursor rules

Cursor reads `.cursorrules` from the project root and `.cursor/rules/*.mdc` for scoped file rules.

**Project install:**

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cp platform-skills/.cursorrules your-project/.cursorrules
mkdir -p your-project/.cursor/rules
cp platform-skills/.cursor/rules/*.mdc your-project/.cursor/rules/
```

Commit those files so every developer gets the rules:

```bash
cd your-project
git add .cursorrules .cursor/rules
git commit -m "chore: add platform-skills cursor rules"
git push
```

**Global install:**

```bash
mkdir -p ~/.cursor/rules
cp platform-skills/.cursor/rules/platform-skills.mdc ~/.cursor/rules/platform-skills.mdc
```

Open Cursor settings and confirm Rules for AI is enabled. Then use Cursor Chat or Agent normally:

```text
Review this Helm chart for securityContext, probes, resources, HPA, PDB, and NetworkPolicy.
```

**Upgrade:**

```bash
cd platform-skills && git pull --ff-only
cp .cursorrules your-project/.cursorrules
cp .cursor/rules/*.mdc your-project/.cursor/rules/
```

---

## Option D — Claude plugin from marketplace

Requires [Claude Code](https://claude.ai/code).

```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

**Verify:**

```bash
claude plugin list
# platform-skills  v1.30.0  enabled
```

**Upgrade:**

```bash
claude plugin marketplace update platform-skills
claude plugin install platform-skills
```

**Uninstall:**

```bash
claude plugin uninstall platform-skills
```

---

## Option E — Claude plugin from local clone

Use this when you want to customise the patterns or test unreleased changes.

```bash
git clone https://github.com/nitinjain999/platform-skills.git
cd platform-skills
claude plugin install .
```

**When to use local vs marketplace:**

| | Marketplace | Local clone |
|---|---|---|
| Easiest setup | ✅ | |
| Customise patterns | | ✅ |
| Test unreleased changes | | ✅ |
| Onboard teammates quickly | ✅ | |

---

## Verify agent integration is working

```bash
cd your-project
claude
```

Then try a concrete prompt:

```
Review this Terraform layout and tell me what should stay in Terraform versus GitOps.
```

```
My Argo CD application is out of sync after a merge. What evidence should I collect first?
```

For Codex, use the same prompts and optionally name the skill explicitly:

```text
Use $platform-skills to review this Terraform layout and tell me what should stay in Terraform versus GitOps.
```

For Cursor, use the same prompts in Cursor Chat or Agent after copying `.cursorrules` and `.cursor/rules/*.mdc`.

---

## Troubleshooting

**`claude plugin install platform-skills` fails with "not found"**

Add the marketplace first:

```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

**Local install fails**

Confirm you are at the repo root:

```bash
ls SKILL.md .claude-plugin/marketplace.json
claude plugin install .
```

**Codex skill does not activate**

Confirm the repo was installed as one skill folder, not just the nested `skills/platform-skills/SKILL.md` file:

```bash
ls "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills/SKILL.md"
ls "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills/references"
ls "${CODEX_HOME:-$HOME/.codex}/skills/platform-skills/agents/openai.yaml"
```

**Cursor rules do not activate**

Confirm the files are in the root of the workspace opened in Cursor:

```bash
ls .cursorrules
ls .cursor/rules/platform-skills.mdc
```

For scoped `.mdc` rules, use Cursor 0.44+ and confirm Rules for AI is enabled in Cursor settings.

**Plugin feels too generic**

Paste the actual file — manifest, Terraform, workflow, or error output. The more concrete the input, the more specific the answer.

---

## Related docs

- [QUICKSTART.md](QUICKSTART.md) — 2-minute start
- [EDITOR_INTEGRATIONS.md](EDITOR_INTEGRATIONS.md) — Copilot, Cursor, JetBrains, Neovim setup
- [GETTING_STARTED.md](GETTING_STARTED.md) — ownership model and how to think about the platform
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to add patterns

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
