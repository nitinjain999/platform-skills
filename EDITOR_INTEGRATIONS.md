# Using Platform Skills in Your Editor

This guide covers how to bring `platform-skills` guidance into the three most common AI-assisted development environments: **GitHub Copilot** (VSCode / JetBrains / CLI), **Cursor**, and **VSCode with Claude Code**.

Each section covers: setup, daily usage, and how to upgrade when a new version is released.

---

## Which tool should I use?

| Scenario | Recommended setup |
|---|---|
| Already using GitHub Copilot | [GitHub Copilot](#github-copilot) — use `copilot-instructions.md` as the context file |
| Using Cursor | [Cursor](#cursor) — use `.cursorrules` or the `@docs` feature |
| Want interactive architecture + troubleshooting | [VSCode + Claude Code](#vscode--claude-code) — install the plugin |
| Team on Copilot, individual on Claude | Run both — Copilot for completions, Claude for design decisions |

---

## GitHub Copilot

### How it works

GitHub Copilot reads `.github/copilot-instructions.md` from your repository root and applies it as workspace context for all completions and chat responses. This repository ships a pre-built `copilot-instructions.md` that encodes the platform engineering rules.

### Setup — Option A: Clone the repo and copy the instructions file

```bash
# Clone platform-skills
git clone https://github.com/nitinjain999/platform-skills.git

# Copy the Copilot instructions file into your project
cp platform-skills/.github/copilot-instructions.md your-project/.github/copilot-instructions.md
```

Commit the file to your repository so every team member gets it automatically.

### Setup — Option B: Reference directly on GitHub (Copilot Enterprise)

If your organization uses GitHub Copilot Enterprise with knowledge bases, add this repository as a knowledge base source:

1. Go to **GitHub organization settings → Copilot → Knowledge bases**
2. Add `https://github.com/nitinjain999/platform-skills` as a source
3. Copilot Enterprise will index `references/` and `examples/` and make them available to `@github` chat

### Setup — Option C: Use the `.github/copilot-instructions.md` file from the repo directly

In VSCode with the GitHub Copilot Chat extension:

1. Open the command palette → **GitHub Copilot: Open Chat**
2. Type `@workspace` to scope responses to your repo
3. The instructions file is picked up automatically from `.github/copilot-instructions.md`

### Daily usage

**Completions** — Copilot will apply the platform rules as you type. For example, generating a `Deployment` will include `resources`, `securityContext`, and probes by default.

**Copilot Chat in VSCode:**

```text
@workspace Using references/terraform.md, generate a Terraform module layout
for an EKS cluster with clear separation between reusable modules and
environment state.
```

```text
@workspace Review this GitHub Actions workflow using .github/copilot-instructions.md.
Flag OIDC gaps, unsafe permissions, and floating action versions.
```

```text
@workspace Using examples/kubernetes/deployment-baseline.yaml, generate a
production-ready Deployment for a Node.js service. Apply the security
context and resource rules from copilot-instructions.md.
```

**Copilot CLI:**

```bash
gh copilot suggest "write a Kyverno ValidatingPolicy that requires team labels on all Deployments"
gh copilot explain "what does prune: true do in a Flux Kustomization"
```

### Upgrade

When a new version of `platform-skills` is released, pull the updated `copilot-instructions.md`:

```bash
# Pull latest from platform-skills
cd platform-skills && git pull origin main

# Copy the updated file to your project
cp .github/copilot-instructions.md your-project/.github/copilot-instructions.md

# Commit the update
cd your-project
git add .github/copilot-instructions.md
git commit -m "chore: update platform-skills copilot-instructions to v<VERSION>"
```

To check what changed between versions, read [CHANGELOG.md](CHANGELOG.md) — each release lists what rules or domains were added.

---

## Cursor

### How it works

Cursor supports two integration points for external knowledge:

1. **`.cursorrules`** — a file in your project root that Cursor reads as global instructions for all AI responses in that workspace
2. **`@docs`** — Cursor can index a URL and make it available as a `@docs` reference in chat

### Setup — Option A: `.cursorrules` file

```bash
# Clone platform-skills
git clone https://github.com/nitinjain999/platform-skills.git

# Generate a .cursorrules file from the skill definition
cat platform-skills/SKILL.md platform-skills/.github/copilot-instructions.md > your-project/.cursorrules
```

Or copy the pre-built rules file directly:

```bash
cp platform-skills/.cursorrules your-project/.cursorrules 2>/dev/null || \
  cp platform-skills/SKILL.md your-project/.cursorrules
```

Commit `.cursorrules` to your repo so all team members get it.

### Setup — Option B: Index with `@docs`

1. Open Cursor → **Settings → Features → Docs**
2. Add a new doc source:
   - **Name:** `platform-skills`
   - **URL:** `https://github.com/nitinjain999/platform-skills`
3. Cursor will crawl and index `references/` and `examples/`
4. In any chat, type `@docs platform-skills` to scope responses to the handbook

### Setup — Option C: Cursor Rules (`.cursor/rules/`)

Cursor 0.44+ supports per-directory rules. Add one rule per domain:

```bash
mkdir -p your-project/.cursor/rules

# Platform-wide rules
cp platform-skills/SKILL.md your-project/.cursor/rules/platform-skills.mdc

# Or individual domain rules
cp platform-skills/references/terraform.md your-project/.cursor/rules/terraform.mdc
cp platform-skills/references/kubernetes.md your-project/.cursor/rules/kubernetes.mdc
```

### Daily usage

**With `.cursorrules`:**

Open any file and start a Cursor chat. The rules are applied automatically.

```text
Generate a Helm values file for a production payment service. Apply the
security and resource defaults from the platform rules.
```

```text
Review this Terraform for blast radius. What resources get replaced?
```

**With `@docs`:**

```text
@docs platform-skills How should I structure a Flux monorepo with three environments?
```

```text
@docs platform-skills What CEL expression checks that a Deployment has a team label?
```

**Inline with `@` reference:**

```text
@platform-skills Write a Kyverno MutatingPolicy that adds default resource limits
to any container that omits them.
```

### Upgrade

```bash
# Pull latest platform-skills
cd platform-skills && git pull origin main

# Regenerate .cursorrules
cat SKILL.md .github/copilot-instructions.md > your-project/.cursorrules

# Or re-index docs in Cursor:
# Settings → Features → Docs → platform-skills → Re-index

# Commit
cd your-project
git add .cursorrules
git commit -m "chore: update platform-skills cursor rules to v<VERSION>"
```

---

## VSCode + Claude Code

### How it works

Claude Code is a terminal-first AI coding assistant. When the `platform-skills` plugin is installed, Claude automatically loads the skill definition and reference guides as context for platform questions. This gives you interactive architecture review, structured troubleshooting, and slash commands directly in the terminal or VSCode extension.

### Setup

**Step 1: Install Claude Code**

```bash
npm install -g @anthropic-ai/claude-code
```

Or download from https://claude.ai/code.

**Step 2: Install the platform-skills plugin**

```bash
# Add the marketplace and install
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills
```

**Step 3: Install the VSCode extension**

1. Open VSCode
2. Press `Ctrl+Shift+X` / `Cmd+Shift+X` to open Extensions
3. Search for **Claude Code**
4. Click **Install**

**Step 4: Verify**

```bash
claude plugin list
# Should show: platform-skills@platform-skills  Version: 1.12.0  Status: enabled
```

### Daily usage

Open the integrated terminal in VSCode (`Ctrl+`` ` ``/ `Cmd+`` ` ``) and run:

```bash
cd your-project
claude
```

**Slash commands** (type at the start of any message):

```text
/platform-skills:review
[paste your Kubernetes manifest or Terraform file]
```

```text
/platform-skills:pr-review full
[paste gh pr diff output]
```

```text
/platform-skills:debug
My Flux Kustomization is stuck in NotReady after merging a PR.
Here is the manifest: [paste]
```

```text
/platform-skills:terraform
[paste Terraform plan output]
```

See [COMMANDS.md](COMMANDS.md) for all available slash commands and their modes.

**From the VSCode Claude Code extension:**

1. Click the Claude Code icon in the Activity Bar
2. Ask in the chat panel — the plugin is already active
3. Reference files directly: `Review @deployment.yaml for production readiness`

### Upgrade

```bash
# Update the marketplace cache
claude plugin marketplace update platform-skills

# Reinstall to get the latest version
claude plugin install platform-skills@platform-skills

# Verify
claude plugin list | grep platform-skills
# Should show the latest version
```

To check what changed: read [CHANGELOG.md](CHANGELOG.md).

---

## JetBrains IDEs (IntelliJ, GoLand, PyCharm, etc.)

### GitHub Copilot in JetBrains

The `.github/copilot-instructions.md` file works the same way as in VSCode:

1. Install the **GitHub Copilot** JetBrains plugin from the marketplace
2. Ensure `.github/copilot-instructions.md` is present in your project root (see [GitHub Copilot](#github-copilot) setup above)
3. Use **Tools → GitHub Copilot → Open Chat** and interact as you would in VSCode

### Claude Code in JetBrains

1. Install the **Claude Code** plugin from the JetBrains marketplace
2. The terminal-installed plugin (`claude plugin install platform-skills`) is shared — no separate install needed
3. Open the Claude Code tool window and use slash commands as normal

---

## Neovim / Emacs / other editors

For editors without a native Copilot or Claude extension, use Claude Code from the terminal alongside your editor:

```bash
# Open Claude in a split terminal
claude
```

The `platform-skills` plugin is active regardless of which editor you use. Paste file contents into the Claude session and ask for review, generation, or debugging.

For Neovim with `copilot.vim` or `copilot.lua`, the `.github/copilot-instructions.md` file is picked up automatically as workspace context.

---

## Upgrade reference

| Tool | Upgrade command |
|---|---|
| Claude Code plugin | `claude plugin marketplace update platform-skills && claude plugin install platform-skills@platform-skills` |
| Copilot instructions | `git pull` in platform-skills clone → copy updated `copilot-instructions.md` to project |
| Cursor `.cursorrules` | `git pull` in platform-skills clone → regenerate `.cursorrules` → commit |
| Cursor `@docs` | Settings → Features → Docs → platform-skills → Re-index |

### How to know when to upgrade

- Watch [GitHub releases](https://github.com/nitinjain999/platform-skills/releases) — subscribe with the **Watch → Releases only** button
- Read [CHANGELOG.md](CHANGELOG.md) before upgrading — each entry lists what domains, commands, and examples were added

### Version pinning

If your team wants to pin to a specific version rather than always using latest:

```bash
# Pin copilot-instructions to a specific tag
git clone --branch v1.12.0 https://github.com/nitinjain999/platform-skills.git

# Pin Claude Code plugin to a specific version (not yet supported natively — install from pinned clone)
git clone --branch v1.12.0 https://github.com/nitinjain999/platform-skills.git pinned-platform-skills
claude plugin install ./pinned-platform-skills
```

---

## Troubleshooting

### Copilot is not applying the platform rules

1. Confirm `.github/copilot-instructions.md` exists in your project root
2. In VSCode, open the file and verify it is not empty
3. Reload the Copilot extension: Command Palette → **Developer: Reload Window**
4. If using Copilot Enterprise knowledge bases, trigger a re-index from your organization settings

### Cursor `@docs` returns stale content

Go to **Settings → Features → Docs → platform-skills → Re-index**. Cursor indexes on demand, not on every update.

### Claude Code plugin shows wrong version

```bash
claude plugin list    # check current version
claude plugin marketplace update platform-skills
claude plugin install platform-skills@platform-skills
claude plugin list    # verify updated
```

### Claude answers too generically

Include more context in your prompt:
- paste the actual file or manifest
- specify the cloud provider and tool versions
- describe the exact error or risk you are investigating

### The skill is not activating automatically

Ask explicitly: *"Using platform-skills, review this Terraform module"*. Automatic activation works best when you paste actual Kubernetes, Terraform, or GitOps file content — plain English questions may not trigger it.

---

## Related docs

- [README.md](README.md) — handbook overview and domain table
- [INSTALLATION.md](INSTALLATION.md) — Claude Code plugin installation detail
- [VSCODE_INTEGRATION.md](VSCODE_INTEGRATION.md) — VSCode-specific patterns
- [COMMANDS.md](COMMANDS.md) — all slash commands and modes
- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) — how the skill and agent work under the hood
- [GETTING_STARTED.md](GETTING_STARTED.md) — first steps for new users
