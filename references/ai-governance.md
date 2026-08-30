# AI Governance

Deep reference for `/platform-skills:ai-governance`. Read `commands/ai-governance.md` first for the wizard; this covers the mechanics behind it.

## Policy schema

```yaml
version: 1
source: local          # "gateway" becomes valid once Phase 3 ships
enforcement: audit     # audit | warn | block
protected_paths:       # glob patterns, matched via a portable `case` statement (works on bash 3.2+)
  - ".github/workflows/**"
denied_commands:       # word-tokenized prefix match — a deterrent, not a security boundary
  - "rm -rf"
max_diff_files: 25      # CI-mode only; evaluated against the total changed-file count in one invocation
require_disclosure: true  # CI-mode only; checks the commit range for an AI-attribution trailer
```

`.ai-governance.yaml` and `.ai-governance/**` belong in every pack's `protected_paths` — this is what lets the *hook itself* deny an agent from editing its own governing policy in real time, rather than relying solely on the merge-time check to catch it after the fact.

### Enforcement tiers and what is actually implemented

| Tier | Hook behavior | CI behavior | Audit outcome recorded |
|------|---------------|-------------|------------------------|
| `audit` | allows, logs | passes, logs | `would_deny` |
| `warn` | allows, logs | passes, logs, **posts a PR comment** | `would_deny_warn` |
| `block` | denies (exit 2) | fails the check (exit 2) | `deny` |

`warn` is a distinct outcome in the log, not a synonym for `audit`. The PR comment is not produced by the evaluator — the evaluator only records `would_deny_warn` lines. `examples/ai-governance/ai-governance-check.yml` reads those lines out of the audit log and posts them with `gh pr comment --edit-last --create-if-none`, which is why the comment behavior lives in the workflow and needs `pull-requests: write` on that job. A hook running in a local session has no PR to comment on, so under `warn` the hook behaves exactly like `audit`; that is a property of where the hook runs, not a gap.

### Self-disable denies regardless of tier

A diff that touches a governance asset — `.ai-governance.yaml`, `.ai-governance/**`, `.github/hooks/**`, `.github/workflows/ai-governance-check.yml`, `.claude/settings.json` — **and** some other protected path is denied by CI mode under every tier, `audit` included. The audit line records outcome `deny` and rule code `self_disable`. Without the override, a team onboarding under `audit` could ship one PR that switched the gate off and changed what it was guarding, and the log would show two harmless `would_deny` lines.

The asset list is hardcoded in `evaluate.sh` (`GOVERNANCE_ASSETS`), not read from the policy, precisely because the policy is one of the things it protects. Touching a governance asset *on its own* is an ordinary `protected_paths` hit and follows the tier as normal — only the combination triggers the override.

## Hook protocol — verified against vendor docs, 2026-08-30

**Copilot** (`docs.github.com/en/copilot/reference/hooks-reference`): stdin carries `toolName`/`toolArgs`, or the snake_case `tool_name`/`tool_input` pair that Claude Code uses; the evaluator reads either. (Event-name casing is a separate axis from payload-key casing: Copilot registers `preToolUse`, Claude Code registers `PreToolUse`.) Output: top-level `permissionDecision` (`allow`/`deny`/`ask`) and `permissionDecisionReason` (required on deny). `command`-type hooks are fail-closed on crash/non-zero exit; **timeouts are always fail-open** — a stalled hook lets the call proceed.

**Claude Code** (`code.claude.com/docs/en/hooks`): stdin carries `tool_name`/`tool_input`. Output: decision nested under `hookSpecificOutput: {hookEventName, permissionDecision, permissionDecisionReason}`. Exit code 2 always blocks, even overriding a JSON `"allow"`. A valid JSON `deny` body at exit 0 is also honored — the JSON decides, not just the exit code. Exit 1, a crash, a missing executable, malformed JSON, or a timeout all default to **allow**.

Net effect: the two failure surfaces point in opposite directions, deliberately. The **hook transport** (Copilot/Claude Code itself) is fail-open on a timeout or crash — a stalled or dead hook lets the call proceed. The **evaluator**, once it actually runs, is fail-closed on its own dependency/policy failures — a missing `yq` or invalid YAML hits `policy_load_failed` and exits 2, not allow. The merge-time check exists to catch what leaks through the transport's fail-open gap; it is not redundant with the hook.

### Registration schema (settings.json) is not the same as the I/O protocol

The runtime protocol above is what crosses stdin/stdout. Registration is a separate schema, and Claude Code's is **three levels deep**, not two: each event key holds an array of *matcher-group* objects, and each matcher group holds its own inner `hooks` array of handler objects.

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

`matcher` is an optional field on the group. Omitting it (or setting `"*"`/`""`) means "match every tool call", which is what this policy wants — every call is evaluated, and the write-intent gate below decides what `protected_paths` applies to. Do not add a `matcher` unless you are deliberately scoping to a subset of tools.

The practical consequence for `generate`: the merge into an existing `.claude/settings.json` has to append a group into `.hooks.<Event>`, which may already contain the user's own matcher groups. `.hooks.PreToolUse = [...]` discards them. `examples/ai-governance/claude-settings-snippet.json` is the shape to copy; `commands/ai-governance.md` step 6 has the `jq` that merges it safely.

Copilot's registration is flat by comparison — `.github/hooks/preToolUse.json` holds `{version, hooks: {preToolUse: [{type, bash, timeoutSec}]}}` — so the two are not interchangeable.

## `protected_paths` gates writes, not reads

The evaluator reads `tool_name`/`toolName` and only applies `protected_paths` when the call has write intent. `Read`, `Glob`, `Grep`, and the other read-only names are allowed through against a protected path even under `block`.

This is a deliberate usability decision with a security rationale: denying a read means a developer cannot open `.github/workflows/release.yml` to look at it, and the predictable response to that is to remove the hook — which is strictly worse than allowing the read. Reading a file the agent can already see in the repo is not the threat model; writing to it is.

Write intent is determined fail-closed in two ways, either of which is sufficient:

- The tool name is not in the read-only set (`read`, `view`, `cat`, `glob`, `grep`, `search`, `find`, `ls`, `list`, `notebookread`, `webfetch`, `websearch`, compared case-insensitively). An unrecognised or absent tool name therefore counts as write intent.
- The payload carries an edit field — `new_string`, `old_string`, `content`, `edits`, or `replace_all` — whatever the tool calls itself.

`denied_commands` is unaffected by this gate. That branch is selected by the presence of a `command` field, before the write-intent check, so a `Bash` call is still evaluated regardless of tool naming.

CI mode has no tool name to inspect and gates on the changed-file list, so every `protected_paths` match in a diff counts there.

## Dry-run mode (`--platform=none`)

`check` mode passes `--platform=none`. That renders a platform-neutral decision instead of either vendor envelope, and suppresses the audit-log write:

```
{"decision":"deny","rule":"protected_paths","reason":"protected_paths: .github/workflows/** (.github/workflows/release.yml)"}
{"decision":"allow"}
```

Exit codes match the real modes (`0` allow, `2` deny), so it is scriptable. Two properties matter: a platform engineer tuning policy gets the rule that fired rather than a transport format, and repeatedly dry-running a policy does not fill the real audit trail with entries for calls that never happened.

`--platform=none` still resolves the enforcement tier. Under `audit` a matching rule renders as `allow`, so testing a rule set in isolation means running `check` against a copy of the policy with `enforcement: block`.

## Trusted verifier (why the merge-time check fetches the base branch)

A PR that edits `.ai-governance.yaml` or `.ai-governance/evaluate.sh` could otherwise weaken the very rule meant to catch that. The merge-time workflow fetches **the base branch's** copy of both files (`git show origin/<base>:<path>`) and runs *that* copy against the PR's diff — trust comes from which copy of the script executes, decided by the workflow YAML, not from extra comparison logic inside the evaluator. This does not fix arbitrary edits to the workflow file itself (a `pull_request`-triggered check on a same-repo branch runs using the PR's modified workflow — a general GitHub Actions limitation). The actual backstop for that is CODEOWNERS-enforced review on the governance-asset paths, which `generate` prints but cannot enforce (branch protection is a repo-admin action).

This also means the check cannot pass on the very first PR that adopts it: `git show origin/<base>:.ai-governance/evaluate.sh` has nothing to read until a copy already exists on the base branch. `commands/ai-governance.md`'s `generate` mode sequences this in two stages — land the evaluator/policy/workflow first, without the check marked required, then require it only once that PR has merged — see its Section 1, step 7.

## `denied_commands` — explicitly scoped

Matching is word-tokenized prefix matching: `terraform apply` matches `terraform apply -auto-approve` but not `terraform -chdir=x apply` (different token at that position) or `terraform_apply_wrapper` (different token entirely). It does not catch aliases, variable expansion, or split flags (`rm -r -f` vs `rm -rf`). This is a documented, intentional limitation — a deterrent against unintentional dangerous commands, not a boundary against a determined actor with push access.

## Audit logging

Written synchronously inside the same invocation that makes the decision — `postToolUse` cannot log a denial on either platform, because a denied call never executes, so neither platform's completion event fires for it. The log (`.ai-governance/audit.log`) is `chmod 600` and gitignored by `generate` — it can contain command text and paths that may carry secrets, so it must never be committed. On the Copilot cloud-agent sandbox, this log is destroyed with the sandbox at job end; it is local, non-durable evidence, not fleet-wide audit — that's Phase 4.

Each line is six tab-separated fields:

```
timestamp   mode   outcome   rule_code   detail   target
```

`rule_code` is a short, stable identifier — one of `protected_paths`, `denied_commands`, `max_diff_files`, `require_disclosure`, `self_disable`, `policy_load_failed`, `post_tool_use` — so log aggregation never parses prose. The human-readable specifics live in `detail`. `outcome` is one of `deny`, `would_deny`, `would_deny_warn`, or `completed`.

CI mode writes **one line per violation**, not one per invocation. Every rule is evaluated in a single pass over the diff — all `protected_paths` matches, then `self_disable`, then `max_diff_files`, then `require_disclosure` — and the decision is rendered once at the end, with the reasons joined by `; ` and the distinct rule codes joined by `,`. Stopping at the first match would mean a diff that trips a protected path never gets its file count checked at all.

### What `postToolUse` does, and does not, do

`--event=postToolUse` (or `PostToolUse`) short-circuits before the policy file is even read. It appends exactly one `completed` / `post_tool_use` line naming the tool and target, emits no decision body, and exits 0.

It deliberately does not re-run the rules. Under `audit` and `warn` the call *is* allowed, so it does complete, so `postToolUse` does fire — and re-deciding there would write a second `would_deny` line for the same call, inflating every violation count by 2x. `PostToolUse` is not a permission event on either platform, so there is nothing for a decision to affect.

## Boundaries with other commands

- `/platform-skills:setup-agents` scaffolds AI tool *config* (AGENTS.md, tool roster). `/platform-skills:ai-governance` scaffolds what those tools are *allowed to do*. Different concern, same repo-scan approach reused, not reimplemented.
- `/platform-skills:opa` is infra/Kubernetes policy-as-code (Rego/Conftest). `/platform-skills:ai-governance` is agent-behavior policy (a bash evaluator against tool calls and diffs). Two different policy engines — do not conflate them.
- `/platform-skills:zizmor` audits workflow *files* for security findings. `/platform-skills:ai-governance` audits agent *actions* taken through those workflows' AI tooling.
- `/platform-skills:pr-review`'s six review dimensions (cost, drift, ownership, compliance, upgrade, rollback) don't cover AI-authorship policy — that's this command's merge-time check, a narrower, separate concern.

## Roadmap

Phase 1 (this doc) has zero infrastructure dependency. Phase 2 (immutable, signed CI verifier), Phase 3 (centrally-distributed policy bundles), and Phase 4 (durable audit ingestion) are separate specs under `docs/superpowers/specs/` — each is optional, and none changes Phase 1's behavior when adopted.
