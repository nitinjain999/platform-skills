---
name: ai-governance
description: Generate and enforce policy gates for AI coding agents (Copilot, Claude Code) — real-time session hooks that deny protected-path edits and dangerous commands, plus a merge-time backstop for anything that bypasses them. Use when asked to "govern AI agents", "block AI from touching secrets", "add an AI policy gate", or "why did the AI agent hook not fire".
argument-hint: "[generate|check|audit|explain] [path]"
title: "AI Governance Command"
sidebar_label: "ai-governance"
custom_edit_url: null
---

Generate and enforce a policy gate for AI coding agents operating on this repo: real-time session hooks for Copilot and Claude Code, plus a merge-time GitHub Actions check that catches anything the hooks miss.

Read `references/ai-governance.md` before responding.

---

## Interactive Wizard (fires when no arguments are provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. generate — scaffold policy, evaluator, hooks, and merge-time check
  2. check    — dry-run the evaluator against a path, command, or diff
  3. audit    — scan repos in an org for policy presence, tier, and drift
  4. explain  — plain-English translation of an existing .ai-governance.yaml

Enter 1-4 or mode name:
```

**Q2 — Context** (after mode selected, one at a time):
- **generate**: `Which default policy pack? (terraform / kubernetes / generic / blank)`
- **check**: `Give me a file path, a command string, or a diff range (e.g. main...HEAD) to test:`
- **audit**: `Which org or repo list should I scan?`
- **explain**: `Path to the .ai-governance.yaml to explain (default: ./.ai-governance.yaml):`

Then proceed into the relevant mode below.

---

## Mode: generate

Scaffold the policy file, evaluator, session hooks, and merge-time check for this repo.

Steps:

1. Detect which AI tools are configured (`.github/copilot/`, `.claude/`, `.cursor/`, `.codex/` if present) and which CI system is in use — reuse the scan approach `setup-agents.md` already implements; do not reimplement it.

2. Write `.ai-governance.yaml` with the chosen default pack. All packs share this shape; only `protected_paths` differs:

   **generic:**
   ```yaml
   version: 1
   source: local
   enforcement: audit
   protected_paths:
     - ".github/workflows/**"
     - ".github/hooks/**"
     - ".claude/settings.json"
     - ".ai-governance.yaml"
     - ".ai-governance/**"
     - "**/secrets/**"
   denied_commands:
     - "rm -rf"
     - "git push --force"
   max_diff_files: 25
   require_disclosure: true
   ```

   **terraform** (adds): `"**/*.tfstate"`, `"iam/**"` to `protected_paths`; adds `"terraform apply"` to `denied_commands`.

   **kubernetes** (adds): `"**/rbac/**"`, `"**/*secret*.yaml"` to `protected_paths`; adds `"kubectl delete"` to `denied_commands`.

   **blank**: same shape, empty `protected_paths`/`denied_commands` — for a team that wants to author its own list from the CODEOWNERS-mandatory paths onward.

3. Copy `examples/ai-governance/evaluate.sh` into `.ai-governance/evaluate.sh` in the target repo, executable bit set (`chmod +x`).

4. Check for `yq` (`command -v yq`); if absent, install it using the OS-detected path (same pattern `checkov.md` uses for its own bootstrap):
   ```bash
   case "$(uname -s)" in
     Darwin) brew install yq ;;
     Linux)
       sudo wget -qO /usr/local/bin/yq \
         "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
       sudo chmod +x /usr/local/bin/yq
       ;;
   esac
   ```

5. Write `.github/hooks/preToolUse.json`:
   ```json
   {
     "version": 1,
     "hooks": {
       "preToolUse": [
         {"type": "command", "bash": ".ai-governance/evaluate.sh --mode=hook --platform=copilot --event=preToolUse", "timeoutSec": 10}
       ]
     }
   }
   ```
   And `.github/hooks/postToolUse.json` (same shape, `--event=postToolUse` — logs completions only, per Section 5 of the spec on why denials can't reach `postToolUse`):
   ```json
   {
     "version": 1,
     "hooks": {
       "postToolUse": [
         {"type": "command", "bash": ".ai-governance/evaluate.sh --mode=hook --platform=copilot --event=postToolUse", "timeoutSec": 10}
       ]
     }
   }
   ```

6. **Merge, never overwrite** `.claude/settings.json`. If the file exists, read it, parse with `jq`, and merge in the hook entries under the existing `hooks` key without touching any other key:
   ```bash
   if [[ -f .claude/settings.json ]]; then
     jq '.hooks.PreToolUse += [{"type":"command","command":".ai-governance/evaluate.sh --mode=hook --platform=claude --event=PreToolUse"}]
         | .hooks.PostToolUse += [{"type":"command","command":".ai-governance/evaluate.sh --mode=hook --platform=claude --event=PostToolUse"}]' \
       .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
   else
     mkdir -p .claude
     cat > .claude/settings.json << 'JSON'
   {
     "hooks": {
       "PreToolUse": [{"type": "command", "command": ".ai-governance/evaluate.sh --mode=hook --platform=claude --event=PreToolUse"}],
       "PostToolUse": [{"type": "command", "command": ".ai-governance/evaluate.sh --mode=hook --platform=claude --event=PostToolUse"}]
     }
   }
   JSON
   fi
   ```

7. Write `.github/workflows/ai-governance-check.yml` (copy from `examples/ai-governance/ai-governance-check.yml`) — this fetches the **base branch's** copy of the evaluator and policy before running, not the PR's own copy (see references/ai-governance.md's "Trusted verifier" section for why).

8. Add `.ai-governance/audit.log` to `.gitignore` — it can contain command text and file paths that may carry secrets, and must never be committed:
   ```bash
   grep -qxF '.ai-governance/audit.log' .gitignore 2>/dev/null || echo '.ai-governance/audit.log' >> .gitignore
   ```

9. Print the exact branch-protection step (Settings → Branches → the target branch's ruleset → require the `ai-governance` check) and the exact CODEOWNERS lines to add:
   ```
   .ai-governance.yaml           @your-org/platform-team
   .ai-governance/               @your-org/platform-team
   .github/hooks/                @your-org/platform-team
   .github/workflows/ai-governance-check.yml  @your-org/platform-team
   .claude/settings.json         @your-org/platform-team
   ```
   State explicitly: this command cannot set branch protection or write CODEOWNERS itself — no repo-admin scope is assumed.

**Validation:**
```bash
printf '%s\0' ".github/workflows/release.yml" | .ai-governance/evaluate.sh --mode=ci --policy=.ai-governance.yaml
# Under enforcement: block → {"permissionDecision":"deny","permissionDecisionReason":"..."}, exit 2
# Under enforcement: audit → {"permissionDecision":"allow"}, plus a would_deny line in .ai-governance/audit.log
```

## Mode: check

Dry-run the evaluator against a path, a command string, or a diff range, without a live agent session.

Steps:

1. Accept a path (file edit test), a command string (bash test), or a diff range (`check --diff main...HEAD`).
2. Run the platform-neutral decision path — never render a Copilot/Claude envelope for this mode, since a platform engineer tuning policy needs the rule that fired, not a vendor transport format:
   ```bash
   # File edit test
   echo '{"toolName":"edit","toolArgs":{"path":"<path>"}}' | .ai-governance/evaluate.sh --mode=hook --platform=copilot

   # Diff range test
   git diff -z --name-only main...HEAD | .ai-governance/evaluate.sh --mode=ci
   ```
3. Report each decision with the matching rule (which `protected_paths` glob or `denied_commands` entry fired), so the policy can be tuned before rollout.

## Mode: audit

Scan repos in an org for policy presence, enforcement tier, and hook/policy drift — no infrastructure required.

Steps:

1. Accept an org or list of repos (`gh api` via existing auth, same pattern as `triage.md`'s comment-fetching).
2. For each repo: check for `.ai-governance.yaml` presence, current `enforcement` tier, and whether the generated hook files match what the current policy would generate (hash comparison, not full regeneration):
   ```bash
   gh api "orgs/<org>/repos" --paginate --jq '.[].full_name' | while read -r repo; do
     policy="$(gh api "repos/$repo/contents/.ai-governance.yaml" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)"
     if [[ -z "$policy" ]]; then
       echo "$repo: not adopted"
     else
       tier="$(echo "$policy" | yq eval '.enforcement' -)"
       echo "$repo: enforcement=$tier"
     fi
   done
   ```
3. Report: adoption rate, tier breakdown, and any repo where hooks are stale relative to its own policy file.

This is the fleet-visibility value normally associated with durable audit ingestion (Phase 4), delivered here via `gh api` with zero infrastructure — it degrades in reach, not in kind, without it.

## Mode: explain

Translate an existing `.ai-governance.yaml` into plain English — same shape as `opa.md`'s `explain` mode.

Steps:

1. Read the policy file.
2. Describe in plain language: what paths are protected and why they matter, what commands are denied and their risk, what enforcement tier is active and what a developer will actually see when a rule fires under that tier, and whether `require_disclosure` is active.
3. If `enforcement: audit`, explicitly say so: "no rule currently blocks anything — violations are logged only."
