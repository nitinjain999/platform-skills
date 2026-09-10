---
name: token-optimizer
description: Route broad repository discovery to a cheaper worker model using each client's native subagents, keeping the main agent for decisions and targeted verification. Use when asked to "reduce token usage", "delegate bulk reading", "set up a cheap reader agent", or "why is my context filling up".
argument-hint: "[inspect|setup|doctor|explain|benchmark|report|disable|remove]"
title: "Token Optimizer Command"
sidebar_label: "token-optimizer"
custom_edit_url: null
---

Route broad repository discovery to a cheaper worker model using each client's native subagent mechanism. Keep the main agent for decisions and targeted verification.

Read `references/token-optimizer.md` before responding.

---

## Interactive Wizard (fires when no arguments are provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. inspect   — detect client, versions, existing agents and hooks, conflicts
  2. setup     — choose scope, worker model, routing mode; write a reviewable diff
  3. doctor    — check delegation, model, redirection, and read limit separately
  4. explain   — dry-run one path or payload: show the rule and proposed decision
  5. benchmark — run a fixture suite in isolated runs and compare
  6. report    — show measured usage and clearly labelled estimates
  7. disable   — turn the optimizer off (enabled: false)
  8. remove    — remove owned, unmodified assets

Enter 1-8 or mode name:
```

**Q2 — Context** (after mode selected, one at a time):
- **setup**: `Which client? (claude / copilot-cli / vscode)` then `Worker model? (claude-haiku-4.5 / gpt-5-mini / gpt-5.4-mini)` then `Routing mode? (audit / redirect — audit recommended for a first install)`
- **explain**: `Give me a file path, or a JSON payload to classify:`
- **benchmark**: `Which fixture suite?` then offer `all` plus every family from `jq -r '[.tasks[].family] | unique | .[]' evals/token-optimizer/manifest.json`
- **report**: no question — reads the log path from the config's `log:` key
- **disable** / **remove**: `Which client's configuration?`

For `setup` on `copilot-cli`, do not offer `redirect`. It is unsupported and the core caps it to audit. Say so rather than accepting the choice and silently downgrading it.

Then proceed into the relevant mode below.

---

## Mode: inspect

Read-only environment scan: detect client, versions, existing agents and hooks, coexistence notes.

Steps:

1. Detect which client is present and report versions:
   ```bash
   # Try each in order
   claude --version 2>/dev/null || echo "claude: not installed"
   copilot --version 2>/dev/null || echo "copilot: not installed"
   code --version 2>/dev/null | head -n1 || echo "vscode: not installed"
   ```

2. Check for existing agent definitions in all locations where clients read them:
   - `.github/agents/` — repository-scoped agents, shared by Copilot CLI and VS Code
   - `~/.copilot/agents/` — user-scoped Copilot CLI agents
   - `.claude/agents/` and `~/.claude/agents/` — repository- and user-scoped Claude Code agents

   List any agent whose name contains `reader`, `bulk`, `worker`, or matches the default `platform-bulk-reader`. Report the agent names found; do not attribute agents in `.github/agents/` to one client from the path alone.

3. Check for existing hooks across **all three** Copilot surfaces (not just one):
   - `.github/hooks/*.json` (repository scope, project-managed)
   - `settings.json` `hooks` key in the repository root (repository scope, alternative location)
   - `~/.copilot/config.json` `hooks` key (user scope, global)

   For Claude Code, check `.claude/settings.json` for matcher groups on `PreToolUse` events.

   Report any hook whose command string contains `optimize.sh` or `token-optimizer`.

4. Check whether an `ai-governance` hook is registered on the same event. This is a coexistence note, not a conflict — the two compose: `ai-governance` governs write intent, `token-optimizer` routes reads. Report it as:
   ```
   Note: ai-governance hook registered on PreToolUse — the two compose (governance
         blocks or logs violations, optimizer delegates reads).
   ```

5. Report the ten largest tracked files, so the operator knows what would be delegated:
   ```bash
   git ls-files | xargs wc -l 2>/dev/null | sort -rn | head -n 10
   ```

6. Check for existing `.token-optimizer.yaml` and `.token-optimizer/` directory. Report current `enabled` and `mode` settings if a config exists.

7. Check for `yq` and `jq` presence:
   ```bash
   command -v yq >/dev/null 2>&1 && echo "yq: installed" || echo "yq: not installed"
   command -v jq >/dev/null 2>&1 && echo "jq: installed" || echo "jq: not installed"
   ```

**Validation:**
Print a summary table:
```
client:       <detected>
version:      <version>
agents found: <count> (<names>)
hooks found:  <count> (<event names>)
config:       present|absent
yq/jq:        both|yq only|jq only|neither
```

## Mode: setup

Install the optimizer: copy assets, write config, register hooks, add ownership markers. The optimizer installs per repository because its config, state directory and hook command are all resolved relative to the repository root.

Steps:

1. Confirm the target client from the wizard answer (claude / copilot-cli / vscode).

2. All assets install to the repository scope: `.token-optimizer/`, `.token-optimizer.yaml`, `.claude/settings.json` or `.github/hooks/`. The optimizer's config and hook are repository-scoped. Agent templates can be installed at user scope (`~/.claude/agents/`, `~/.copilot/agents/`), but the core and its config remain repository-relative.

3. Confirm the worker model. Verified valid on Copilot CLI 1.0.59: `claude-haiku-4.5`, `gpt-5-mini`, `gpt-5.4-mini`. On Claude Code use `haiku` or a concrete model id your provider exposes. Only the VS Code coordinator pins a model (`claude-sonnet-4.6`); the Copilot CLI coordinator sets none and inherits the session's, and Claude Code ships no coordinator at all.

4. Confirm the routing mode: `audit` or `redirect`.
   - **audit**: logs oversized-read opportunities, denies nothing (default, recommended for a first install)
   - **redirect**: denies an oversized read with a reason naming the worker and carrying the contract

   **CRITICAL on copilot-cli**: if the client is `copilot-cli`, refuse the `redirect` choice and set `audit` instead. Redirection is unsupported on Copilot CLI because the documented `preToolUse` payload carries no per-call worker identity, so the worker cannot be reliably exempted. Say this explicitly rather than accepting the choice and silently downgrading it.

5. Install the core script:
   ```bash
   mkdir -p .token-optimizer
   cp examples/token-optimizer/optimize.sh .token-optimizer/optimize.sh
   chmod +x .token-optimizer/optimize.sh
   ```

6. Write `.token-optimizer.yaml` with the chosen settings. Default to `mode: audit` unless the operator explicitly chose `redirect` and the client supports it.

   **Before writing `mode: redirect` for Claude Code**, check the probe fixture:
   ```bash
   # For Claude Code only
   if [[ "$client" == "claude" && "$chosen_mode" == "redirect" ]]; then
     installed_version="$(claude --version 2>/dev/null | head -1)"
     fixture_path=".token-optimizer/probe/fixture.json"
     if [[ -r "$fixture_path" ]]; then
       verified="$(jq -r '.delegation_verified' "$fixture_path" 2>/dev/null)"
       fixture_client_version="$(jq -r '.client_version' "$fixture_path" 2>/dev/null)"
       if [[ "$verified" != "true" || "$fixture_client_version" != "$installed_version" ]]; then
         echo "Delegation unverified — setting mode: audit instead of redirect."
         echo "Run .token-optimizer/probe/run-probe.sh to verify delegation, then re-run setup."
         chosen_mode="audit"
       fi
     else
       echo "Probe fixture not found — setting mode: audit instead of redirect."
       echo "Run .token-optimizer/probe/run-probe.sh to verify delegation, then re-run setup."
       chosen_mode="audit"
     fi
   fi
   ```
   If the probe is unverified or the client version mismatches, write `mode: audit` and tell the user why, naming the command to run.
   ```yaml
   # OWNERSHIP MARKER: platform-skills token-optimizer v1.41.0
   version: 1
   enabled: true
   mode: audit
   worker_agent: platform-bulk-reader
   worker_model: claude-haiku-4.5
   max_lines: 350
   max_bytes: 32768
   max_range_ratio: 80
   default_read_limit: 0
   summary_words: 600
   cumulative_lines: 8000
   cumulative_bytes: 524288
   max_delegations_per_task: 3
   max_worker_retries: 1
   max_worker_seconds: 120
   exempt_agent_types:
     - platform-bulk-reader
   log: .token-optimizer/decisions.log
   state_dir: .token-optimizer/state
   ```

7. **Create `.token-optimizer/` and `.token-optimizer/state/` directories.** The core deliberately never creates its own directories, and bounded recovery cannot function without the state directory — without it the core refuses to redirect at all:
   ```bash
   mkdir -p .token-optimizer/state
   ```

8. **Copy the delegation probe** into `.token-optimizer/probe/` so `doctor` can read a repository-local fixture:
   ```bash
   mkdir -p .token-optimizer/probe
   cp examples/token-optimizer/claude/probe/run-probe.sh .token-optimizer/probe/run-probe.sh
   cp examples/token-optimizer/claude/probe/fixture.json .token-optimizer/probe/fixture.json
   chmod +x .token-optimizer/probe/run-probe.sh
   ```
   The probe script resolves its output path relative to its own location, so running `.token-optimizer/probe/run-probe.sh` updates `.token-optimizer/probe/fixture.json`.

9. Register the PreToolUse hook by **appending**, never overwriting. Existing hooks for other features (e.g., `ai-governance`) must remain intact.

   **For Claude Code**, use the three-level matcher-group structure and the `jq` idiom from `commands/ai-governance.md:142-151`:
   ```bash
   PRE_CMD='.token-optimizer/optimize.sh --mode=hook --platform=claude'

   mkdir -p .claude
   [[ -f .claude/settings.json ]] || echo '{}' > .claude/settings.json

   jq --arg pre "$PRE_CMD" '
     def add_group($event; $cmd):
       if [ (.hooks[$event] // [])[] | (.hooks // [])[]? | select(.command == $cmd) ] | length > 0
       then .
       else .hooks[$event] = ((.hooks[$event] // []) + [{"hooks": [{"type": "command", "command": $cmd}]}])
       end;
     add_group("PreToolUse"; $pre)
   ' .claude/settings.json > .claude/settings.json.tmp \
     && mv .claude/settings.json.tmp .claude/settings.json
   ```

   **For Copilot CLI**, register on **all three** surfaces. Check each for existing entries and append only where missing:

   a. Repository `.github/hooks/preToolUse.json`:
   ```bash
   mkdir -p .github/hooks
   [[ -f .github/hooks/preToolUse.json ]] || echo '{}' > .github/hooks/preToolUse.json

   jq --arg cmd '.token-optimizer/optimize.sh --mode=hook --platform=copilot' '
     def has_hook($arr; $cmd):
       $arr | map(select(.bash == $cmd or .command == $cmd)) | length > 0;
     
     . as $root |
     if ($root.hooks.preToolUse // [] | length) == 0
     then $root | .version = ($root.version // 1) | .hooks.preToolUse = [{"type": "command", "bash": $cmd, "timeoutSec": 5}]
     elif has_hook($root.hooks.preToolUse; $cmd)
     then $root
     else $root | .hooks.preToolUse = ((.hooks.preToolUse // []) + [{"type": "command", "bash": $cmd, "timeoutSec": 5}])
     end
   ' .github/hooks/preToolUse.json > .github/hooks/preToolUse.json.tmp \
     && mv .github/hooks/preToolUse.json.tmp .github/hooks/preToolUse.json \
     || rm -f .github/hooks/preToolUse.json.tmp
   ```

   b. Repository `settings.json` `hooks` key (if present) — merge using `jq`.

   c. User `~/.copilot/config.json` `hooks` key (only if the user wants the optimizer active across all their repositories, and only alongside a repository-scoped install in each) — merge using `jq`.

   **For VS Code**, note that agent-scoped hooks are a preview feature gated on `chat.useCustomAgentHooks`. If that setting is not enabled, the hooks will not fire. Report this as a post-setup instruction.

10. Copy the client's agent templates. The optimizer's own config, state directory and hook command are repository-scoped, but agent definitions can additionally be installed user-wide, so both destinations are listed where a client supports them:
   - **Claude Code** (repository): copy `examples/token-optimizer/claude/platform-bulk-reader.md` to `.claude/agents/platform-bulk-reader.md`
   - **Claude Code** (user): copy to `~/.claude/agents/platform-bulk-reader.md`
   - **Copilot CLI** (repository): copy both `examples/token-optimizer/copilot-cli/platform-bulk-reader.agent.md` and `examples/token-optimizer/copilot-cli/platform-coordinator.agent.md` to `.github/agents/`
   - **Copilot CLI** (user): copy both to `~/.copilot/agents/`
   - **VS Code** (repository): copy both `examples/token-optimizer/vscode/platform-bulk-reader.agent.md` and `examples/token-optimizer/vscode/platform-coordinator.agent.md` to `.github/agents/`

11. Add an ownership marker to every generated asset (YAML, JSON, agent templates) as a comment or frontmatter field:
    ```
    # OWNERSHIP MARKER: platform-skills token-optimizer v1.41.0
    ```
    This is what `remove` uses to identify assets safe to delete.

12. Add runtime state to `.gitignore`, but explicitly do not ignore the script itself (the committed hook invokes it):
    ```bash
    grep -qxF '.token-optimizer/decisions.log' .gitignore 2>/dev/null || echo '.token-optimizer/decisions.log' >> .gitignore
    grep -qxF '.token-optimizer/state/' .gitignore 2>/dev/null || echo '.token-optimizer/state/' >> .gitignore
    grep -qxF '.token-optimizer/probe/' .gitignore 2>/dev/null || echo '.token-optimizer/probe/' >> .gitignore
    grep -qxF '!.token-optimizer/optimize.sh' .gitignore 2>/dev/null || echo '!.token-optimizer/optimize.sh' >> .gitignore
    ```
    The script is committed deliberately because the committed hook invokes it. The probe directory is gitignored because `doctor` runs it locally.

13. Print a reviewable diff summary:
    ```bash
    git status --short
    git diff --stat
    ```

14. State explicitly that Copilot CLI is audit-only regardless of the configured mode, if the client is `copilot-cli`.

**Validation:**
```bash
[[ -f .token-optimizer/optimize.sh && -x .token-optimizer/optimize.sh ]] && echo "core script: installed"
[[ -f .token-optimizer.yaml ]] && echo "config: written"
[[ -d .token-optimizer/state ]] && echo "state directory: created"
yq eval '.enabled, .mode' .token-optimizer.yaml
```

## Mode: doctor

Check delegation, model, redirection, and read limit separately. Report four states on separate lines and never collapse them.

Steps:

1. **delegation verified** — read `.token-optimizer/probe/fixture.json` and require ALL of:
   - `delegation_verified == true`
   - `client_version` matches the installed `claude --version`
   - `probe_version` matches the version `doctor` expects (currently `1`)

   Any mismatch, including a client upgrade, reports `no (runtime fixture required)`. The shipped fixture is deliberately un-run, so on a fresh install this reads `no`.

   On Copilot CLI and VS Code, report `no (unsupported)` because delegation is unverified on those clients.

   ```bash
   # On Claude Code
   installed_version="$(claude --version 2>/dev/null | head -1)"
   fixture_path=".token-optimizer/probe/fixture.json"
   if [[ -r "$fixture_path" ]]; then
     verified="$(jq -r '.delegation_verified' "$fixture_path")"
     fixture_client_version="$(jq -r '.client_version' "$fixture_path")"
     probe_version="$(jq -r '.probe_version' "$fixture_path")"
     if [[ "$verified" == "true" && "$fixture_client_version" == "$installed_version" && "$probe_version" == "1" ]]; then
       echo "delegation verified:      yes"
     else
       echo "delegation verified:      no (runtime fixture required)"
     fi
   else
     echo "delegation verified:      no (runtime fixture required)"
   fi
   ```

2. **worker model resolved** — read the config's `worker_model` and report what the client would resolve it to. On Claude Code, the agent definition's frontmatter `model:` field is the request, and the resolved model depends on the provider. On Copilot CLI, the requested model is directly in the config.

   When resolution cannot be observed from static files (e.g., Bedrock mapping is account-specific), print `unverified` and make **no** cheaper-routing claim:
   ```
   worker model resolved:    unverified (Bedrock mapping is account-specific)
   ```

   When resolution is known:
   ```
   worker model resolved:    claude-haiku-4.5 (source: config)
   ```

3. **read redirection active** — check the effective mode and platform caps, passing the actual client being inspected:
   ```bash
   # For Claude Code
   .token-optimizer/optimize.sh --mode=explain --platform=claude --path=/dev/null | grep "^effective mode:"
   # For Copilot CLI
   .token-optimizer/optimize.sh --mode=explain --platform=copilot --path=/dev/null | grep "^effective mode:"
   # For VS Code
   .token-optimizer/optimize.sh --mode=explain --platform=vscode --path=/dev/null | grep "^effective mode:"
   ```
   Report:
   - `yes` — config says `redirect` and the platform supports it
   - `no (audit only)` — config says `audit` or the platform capped `redirect` to `audit`
   - `no (unsupported on this client)` — Copilot CLI or VS Code

4. **default read limit** — report the client's default read limit as measured or assumed:
   ```
   default read limit:       2000 (measured, Claude Code)
   default read limit:       0 (assumed, unknown client)
   ```

5. Additionally report:
   - `yq` and `jq` presence
   - Config schema version (read `.version` from `.token-optimizer.yaml`)
   - `enabled` state (read `.enabled`)
   - Effective mode plus the cap reason, if any (from `optimize.sh --mode=explain`)
   - Whether `.token-optimizer/state/` exists (without it recovery cannot bound and the core will not redirect)
   - Whether `chat.useCustomAgentHooks` is set on VS Code (required for agent-scoped hooks)
   - Whether `disableAllHooks` is set in Copilot's config (if true, no hooks fire at all)
   - Whether each worker budget is natively enforced or instruction-only (on Claude Code, agent-level `max_tokens`, `timeout`, and `max_iterations` are natively enforced; on other clients, budgets are instruction-only)

**Validation:**
```
delegation verified:      yes | no (runtime fixture required) | no (unsupported)
worker model resolved:    <resolved> (source: <how>) | unverified
read redirection active:  yes | no (audit only) | no (unsupported on this client)
default read limit:       <n> (measured) | <n> (assumed) | unknown
```

## Mode: explain

Dry-run one path or payload: show the rule and proposed decision. Runs no worker, writes no log, records no recovery state.

Steps:

1. Accept a file path via `--path=`, or read a JSON payload from stdin.

2. Shell out to `optimize.sh --mode=explain` and pass the input. Use `--platform=none` only where a deliberately vendor-neutral rule line is wanted; otherwise pass the actual client (`--platform=claude|copilot|vscode`) to see its effective mode and platform caps:
   ```bash
   # File path
   .token-optimizer/optimize.sh --mode=explain --platform=claude --path=<path>

   # JSON payload
   echo '<payload>' | .token-optimizer/optimize.sh --mode=explain --platform=claude
   ```

3. Print the output, which includes:
   - path
   - total lines
   - requested lines
   - requested bytes (measured, not estimated)
   - whether it counts as a whole file (ratio threshold reporting only)
   - max_lines and max_bytes thresholds
   - default_read_limit for the platform
   - configured mode
   - effective mode (with cap reason, if any)
   - enabled state
   - worker agent and model (requested; not verified)
   - worker budgets
   - cumulative limits (advisory)
   - classification (pass | oversized)
   - decision (pass | audit | redirect)
   - degraded status

4. Interpret the output for the operator:
   - **Which gate fired?** If `classification: oversized`, which threshold was exceeded (max_lines or max_bytes)?
   - **Did the platform cap the mode?** If `effective mode` differs from `configured mode`, explain the cap reason.
   - **What to change to alter the outcome?** Raise the threshold, switch to redirect mode, or verify delegation.

**Validation:**
The dry run writes no log and no state. Verify by checking that `.token-optimizer/decisions.log` and `.token-optimizer/state/` have not changed since the explain run.

## Mode: benchmark

Orchestrate isolated fixture runs across four arms, compare token usage. Three runs per task, randomized order, declared cache state, appending JSONL.

Steps:

1. Confirm which fixture suite to run. Offer `all` plus the manifest's actual family ids, derived rather than hardcoded: `jq -r '[.tasks[].family] | unique | .[]' evals/token-optimizer/manifest.json` yields `difficult-reasoning-control`, `github-actions`, `helm-gitops`, `scanner-results`, `small-task-control`, `source-navigation`, `terraform-discovery`.

2. Read `evals/token-optimizer/manifest.json` to retrieve:
   - Arms: `baseline`, `concise`, `delegated`, `native`
   - Task list (filtered by suite if not `all`)
   - Run count (default 3)
   - Record fields

3. For each task in the selected suite, run four mutually exclusive arms in randomized order:
   - **Baseline** — no delegation, no read interception (optimizer disabled)
   - **Concise** — `mode: advisory`, instructions only
   - **Delegated** — `mode: redirect`, actual worker dispatch
   - **Native** — the client's own built-in discovery agent, where one exists

4. For each run, construct an isolated scratch workspace containing ONLY:
   - The fixture's `task.md` (the agent's instructions)
   - The fixture's `evidence/` directory (files the agent must read)
   - Do NOT include `criteria.json` — it must not be readable by the agent under test

5. Declare `cache_state` explicitly as `cold`, `warm`, or `unknown` rather than inferring it. A run immediately after session start is `cold`. A run after a previous task has warmed the cache is `warm`. If cache state cannot be established, write `unknown`.

6. After each run completes, append one JSONL record with these fields:
   - `client`, `client_version`, `plugin_version`
   - `task_id` (fixture name)
   - `arm` (baseline | concise | delegated | native)
   - `run_index`, `cache_state` (cold | warm | unknown)
   - `repo_commit`, `dirty_file_hashes`
   - `parent_model_requested`, `parent_model_resolved`
   - `worker_model_requested`, `worker_model_resolved`
   - `model_verification_source`, `model_fallback_reason`
   - `elapsed_seconds` (wall-clock time from task start to completion)
   - `delegation_count`, `retries` (count of worker retries, if observable)
   - `parent_input_tokens`, `parent_cache_write_tokens`, `parent_cache_read_tokens`, `parent_output_tokens`
   - `worker_input_tokens`, `worker_cache_write_tokens`, `worker_cache_read_tokens`, `worker_output_tokens` (zero only for baseline/concise where no worker ran; for native, record measured usage if exposed or "unavailable" if not)
   - `external_service_charges`, `pricing_date`
   - `evidence_verdict`, `evidence_score`
   - `outcome` (whether the task completed successfully)

7. **Never fabricate a token count.** When a client exposes no usage figure, write `"unavailable"` (string) in that field, not an estimate or zero. When cache state cannot be established, write `"unknown"` rather than guessing.

8. These benchmarks require provider credentials, coordinator and worker sessions, and controlled task selection. They do NOT run by default in this repository. State this explicitly when reporting results: no savings figure is published in v1.41.0.

**Validation:**
Check that every row carries the manifest's `record_fields` and no others. Verify with `jq -r '.record_fields[]' evals/token-optimizer/manifest.json` and compare against the keys actually written. There is no `total_tokens` field: cost is derived per actor from the four billing-unit fields (`*_input_tokens`, `*_cache_write_tokens`, `*_cache_read_tokens`, `*_output_tokens`), and `retries` is diagnostic only and never added to a cost total.

## Mode: report

Aggregate the decision log into a summary table. Keep measured, estimated, and unavailable visually distinct. Reads whatever `log:` the config names.

Steps:

1. Read the log path from `.token-optimizer.yaml` `log:` key (default: `.token-optimizer/decisions.log`).

2. Shell out to `optimize.sh --mode=report`:
   ```bash
   .token-optimizer/optimize.sh --mode=report --config=.token-optimizer.yaml
   ```

3. The script prints a summary table of decision events:
   ```
   outcome              count
   -------------------- -----
   would_redirect          12
   redirect                 3
   cumulative_exceeded      1
   ```

4. Additionally aggregate the benchmark JSONL (if it exists) and print:
   - Median total tokens per arm
   - Cache state breakdown (cold | warm | unknown)
   - Retries and failures
   - Both formulas, from the manifest's `cost_model`:
     - `actor_cost = sum over billing units of (tokens x rate for that unit at pricing_date)`, where an actor is `parent` or `worker` and the units are `input_tokens`, `cache_write_tokens`, `cache_read_tokens`, `output_tokens`
     - `total_cost = parent cost + worker cost + external_service_charges`

5. **Refuse to compute a percentage when the baseline is zero.** If the baseline arm has zero measured tokens (e.g., no runs or all unavailable), report the absolute numbers only and state:
   ```
   Baseline total is zero or unavailable — no percentage can be computed.
   ```

6. **Compare cold against cold and warm against warm only.** Do not mix cache states when computing a reduction percentage.

7. Clearly label which figures are:
   - **measured** — directly from the provider's usage API
   - **estimated** — computed from a formula or proxy
   - **unavailable** — client exposes no usage figure

8. Include retries and failures in the report, so operators know how often the worker had to retry or gave up.

**Validation:**
```bash
grep -c "would_redirect" .token-optimizer/decisions.log
grep -c "redirect" .token-optimizer/decisions.log
```

## Mode: disable

Turn the optimizer off by setting `enabled: false`. Additionally deactivate owned routing-instruction blocks by ownership marker.

Steps:

1. Confirm which client's configuration to disable (claude / copilot-cli / vscode).

2. Set `enabled: false` in `.token-optimizer.yaml`:
   ```bash
   yq eval '.enabled = false' -i .token-optimizer.yaml
   ```

3. Additionally, deactivate any routing-instruction blocks in the agent definitions that carry the ownership marker. Comment them out or remove them, but leave the agent definition itself (other features may use it).

4. Report whether a running session must be restarted for the change to take effect:
   - **Claude Code**: the hook is re-loaded on every tool call, so the change is immediate
   - **Copilot CLI**: hooks are loaded at session start, so a restart is required
   - **VS Code**: hooks are loaded at session start, so a restart is required

5. **Warn that Copilot's `disableAllHooks` is not optimizer-scoped.** Setting it to `true` would disable the `ai-governance` hook too (if present) and any other hooks registered. Offer per-hook removal instead and never set `disableAllHooks` silently:
   ```
   Warning: Copilot's `disableAllHooks: true` is not feature-scoped and would
            disable ai-governance too. Use the `remove` mode to delete individual
            hook entries instead.
   ```

**Validation:**
```bash
yq eval '.enabled' .token-optimizer.yaml
# → false
```

## Mode: remove

Remove assets carrying the ownership marker. The marker is authoritative: `setup` injects it, so no shipped-file hash can ever match a generated asset, and gating deletion on a hash match would make uninstall silently inert. A marked asset whose content differs from what `setup` would generate is still removed, and reported as locally modified. An asset with no marker is never touched, only listed for manual review.

Steps:

1. Confirm which client's configuration to remove (claude / copilot-cli / vscode).

2. Scan for assets with the ownership marker `# OWNERSHIP MARKER: platform-skills token-optimizer v1.41.0`. Candidates:
   - `.token-optimizer.yaml`
   - `.token-optimizer/optimize.sh`
   - `.token-optimizer/probe/run-probe.sh` and `.token-optimizer/probe/fixture.json`
   - `.claude/agents/platform-bulk-reader.md` and `~/.claude/agents/platform-bulk-reader.md`
   - `.github/agents/platform-bulk-reader.agent.md` and `.github/agents/platform-coordinator.agent.md` (Copilot CLI and VS Code)
   - `~/.copilot/agents/platform-bulk-reader.agent.md` and `~/.copilot/agents/platform-coordinator.agent.md` (user-scoped)
   - Hook entries in `.claude/settings.json`, `.github/hooks/*.json`, repository root `settings.json` `hooks` key, `~/.copilot/config.json`

3. For each asset carrying the ownership marker:
   - Remove it immediately
   - If the asset's content differs from what `setup` would generate (compare against `examples/token-optimizer/`), report it as "removed (locally modified)"
   - The ownership marker is authoritative because `setup` injects it, so no shipped-file hash can match a generated asset
   
   For assets with no ownership marker:
   - Never touch them
   - List them for manual review

4. For hook entries in JSON files, remove the specific hook command that matches `.token-optimizer/optimize.sh`, not the entire hooks array. Other features' hooks must remain intact.

5. **Leave `.token-optimizer/decisions.log` in place unless explicitly asked.** It contains audit history that may be needed for review or compliance. State this when reporting what was removed.

6. Remove the `.token-optimizer/state/` and `.token-optimizer/probe/` directories after confirming no other feature uses them.

7. Remove `.token-optimizer/` entries from `.gitignore` if they were added by `setup`.

**Validation:**
```bash
[[ ! -f .token-optimizer.yaml ]] && echo "config: removed"
[[ ! -f .token-optimizer/optimize.sh ]] && echo "core script: removed"
[[ ! -d .token-optimizer/state ]] && echo "state directory: removed"
git status --short
```
