# Installation Guide

This is the canonical install reference for platform-skills.

**No installation needed to use the handbook.** Browse [references/](references/) and [examples/](examples/) directly on GitHub.
Install only if you want the Claude plugin for interactive guidance.

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

## Option B — Claude plugin from marketplace

Requires [Claude Code](https://claude.ai/code).

```bash
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

**Verify:**

```bash
claude plugin list
# platform-skills  v1.16.0  enabled
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

## Option C — Claude plugin from local clone

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

## Verify Claude plugin is working

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
