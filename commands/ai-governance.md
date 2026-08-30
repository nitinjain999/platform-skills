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

4. Check for `yq` (`command -v yq`); if absent, install it using the OS-detected path (same pattern `checkov.md` uses for its own bootstrap). Pin the version and verify the checksum — `releases/latest` is a moving target, and this binary parses the file that decides what the agent may touch:
   ```bash
   YQ_VERSION=v4.53.6
   YQ_SHA256=c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385  # yq_linux_amd64

   case "$(uname -s)" in
     Darwin) brew install yq ;;   # Homebrew verifies its own bottle checksum
     Linux)
       curl -fsSL -o /tmp/yq \
         "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
       echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c -
       sudo install -m 0755 /tmp/yq /usr/local/bin/yq
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
   And `.github/hooks/postToolUse.json` (same shape, `--event=postToolUse`). This one is not a second gate. `--event=postToolUse` short-circuits before the policy is even loaded: it appends one `completed` line to the audit log, emits no decision, and exits 0. It never re-evaluates `protected_paths` or `denied_commands` — the call has already run by then, and re-deciding would duplicate the audit line `preToolUse` already wrote for the same call under `audit` or `warn`:
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

6. **Merge, never overwrite** `.claude/settings.json`.

   Claude Code's `settings.json` hook registration is **three levels deep**, not two: each event key holds an array of *matcher-group* objects, and each matcher group holds its own inner `hooks` array of handler objects. `matcher` is optional — omitting it means "match every tool call", which is what this policy wants (every call gets evaluated, not just one tool):
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "hooks": [
             {"type": "command", "command": ".ai-governance/evaluate.sh --mode=hook --platform=claude --event=PreToolUse"}
           ]
         }
       ]
     }
   }
   ```

   Merge into that structure with `jq`, appending a new matcher group whether or not the event key already has entries, and skipping the append if this exact command is already registered so re-running `generate` is idempotent:
   ```bash
   PRE_CMD='.ai-governance/evaluate.sh --mode=hook --platform=claude --event=PreToolUse'
   POST_CMD='.ai-governance/evaluate.sh --mode=hook --platform=claude --event=PostToolUse'

   mkdir -p .claude
   [[ -f .claude/settings.json ]] || echo '{}' > .claude/settings.json

   jq --arg pre "$PRE_CMD" --arg post "$POST_CMD" '
     def add_group($event; $cmd):
       if [ (.hooks[$event] // [])[] | (.hooks // [])[]? | select(.command == $cmd) ] | length > 0
       then .
       else .hooks[$event] = ((.hooks[$event] // []) + [{"hooks": [{"type": "command", "command": $cmd}]}])
       end;
     add_group("PreToolUse"; $pre) | add_group("PostToolUse"; $post)
   ' .claude/settings.json > .claude/settings.json.tmp \
     && mv .claude/settings.json.tmp .claude/settings.json
   ```

   `(.hooks[$event] // [])` is what makes this safe on a file that has no `hooks` key, has `hooks` but not this event, or already has other matcher groups registered for this event. Never write `.hooks.PreToolUse = [...]` — that discards any matcher group the user already had.

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
# Under enforcement: warn  → {"permissionDecision":"allow"}, plus a would_deny_warn line in .ai-governance/audit.log
#                            (the workflow reads those lines and posts the PR comment)
# Under enforcement: audit → {"permissionDecision":"allow"}, plus a would_deny line in .ai-governance/audit.log
```

One exception to the tier table, worth stating when you hand this over: a diff that touches a governance asset (`.ai-governance.yaml`, `.ai-governance/**`, `.github/hooks/**`, `.github/workflows/ai-governance-check.yml`, `.claude/settings.json`) **and** another protected path denies under every tier, `audit` included. Otherwise a single PR could switch off the gate and change what it was guarding at the same time. Changing a governance asset on its own is an ordinary `protected_paths` hit and follows the tier as normal.

## Mode: check

Dry-run the evaluator against a path, a command string, or a diff range, without a live agent session.

Steps:

1. Accept a path (file edit test), a command string (bash test), or a diff range (`check --diff main...HEAD`).
2. Always pass `--platform=none`. That is the evaluator's platform-neutral renderer: it prints `{"decision":…,"rule":…,"reason":…}` instead of a Copilot or Claude envelope, because a platform engineer tuning policy needs the rule that fired, not a vendor transport format. It also writes nothing to `.ai-governance/audit.log`, so a dry run never leaves fake entries in the real audit trail:
   ```bash
   # File edit test — an edit payload, so this is write intent
   echo '{"toolName":"edit","toolArgs":{"path":".github/workflows/release.yml","content":"x"}}' \
     | .ai-governance/evaluate.sh --mode=hook --platform=none
   # → {"decision":"deny","rule":"protected_paths","reason":"protected_paths: .github/workflows/** (.github/workflows/release.yml)"}

   # Command string test — denied_commands, not protected_paths
   echo '{"toolName":"bash","toolArgs":{"command":"terraform apply -auto-approve"}}' \
     | .ai-governance/evaluate.sh --mode=hook --platform=none
   # → {"decision":"deny","rule":"denied_commands","reason":"denied_commands: terraform apply"}

   # Diff range test — every rule evaluated in one pass, codes joined and deduped
   git diff -z --name-only main...HEAD \
     | .ai-governance/evaluate.sh --mode=ci --platform=none
   # → {"decision":"deny","rule":"protected_paths,max_diff_files","reason":"protected_paths: iam/** (iam/policy.json); max_diff_files: 31 > 25"}
   ```
   Exit code is `0` for allow and `2` for deny, so this is scriptable.
3. Report each decision with the matching rule (which `protected_paths` glob or `denied_commands` entry fired), so the policy can be tuned before rollout.
4. Two things to say out loud when reporting, because they change what the result means:
   - A `deny` here is what the rules say, **not** what the current tier does. `--platform=none` reports the tier-resolved decision, so under `enforcement: audit` or `warn` a matching rule renders as `allow` — run `check` against a copy of the policy with `enforcement: block` to see the rule set on its own.
   - `protected_paths` only fires on write intent. A `Read` against a protected path is allowed by design, so testing with a read-shaped payload will always come back `allow`.

## Mode: audit

Scan repos in an org for policy presence, enforcement tier, and hook/policy drift — no infrastructure required.

Steps:

1. Accept an org or list of repos (`gh api` via existing auth, same pattern as `triage.md`'s comment-fetching).
2. For each repo: check for `.ai-governance.yaml` presence, current `enforcement` tier, and whether the generated hook files match what the current policy would generate (hash comparison, not full regeneration):
   Ask the API for the raw file rather than fetching base64 `.content` and decoding it — the decode flag is `-d` on GNU coreutils and `-D` on macOS/BSD, so a decode step here is a portability bug waiting on whoever runs it next:
   ```bash
   gh api "orgs/<org>/repos" --paginate --jq '.[].full_name' | while read -r repo; do
     policy="$(gh api "repos/$repo/contents/.ai-governance.yaml" \
       -H "Accept: application/vnd.github.raw" 2>/dev/null)"
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
