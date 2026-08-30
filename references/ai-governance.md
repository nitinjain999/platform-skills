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

## Hook protocol — verified against vendor docs, 2026-08-30

**Copilot** (`docs.github.com/en/copilot/reference/hooks-reference`): stdin carries `toolName`/`toolArgs` (camelCase hook config) or `tool_name`/`tool_input` (PascalCase config). Output: top-level `permissionDecision` (`allow`/`deny`/`ask`) and `permissionDecisionReason` (required on deny). `command`-type hooks are fail-closed on crash/non-zero exit; **timeouts are always fail-open** — a stalled hook lets the call proceed.

**Claude Code** (`code.claude.com/docs/en/hooks`): stdin carries `tool_name`/`tool_input`. Output: decision nested under `hookSpecificOutput: {hookEventName, permissionDecision, permissionDecisionReason}`. Exit code 2 always blocks, even overriding a JSON `"allow"`. A valid JSON `deny` body at exit 0 is also honored — the JSON decides, not just the exit code. Exit 1, a crash, a missing executable, malformed JSON, or a timeout all default to **allow**.

Net effect: this design is fail-closed for cases it controls (the evaluator's own logic), and explicitly fail-open on infrastructure failure. The merge-time check exists specifically to catch what leaks through that gap — it is not redundant with the hook.

## Trusted verifier (why the merge-time check fetches the base branch)

A PR that edits `.ai-governance.yaml` or `.ai-governance/evaluate.sh` could otherwise weaken the very rule meant to catch that. The merge-time workflow fetches **the base branch's** copy of both files (`git show origin/<base>:<path>`) and runs *that* copy against the PR's diff — trust comes from which copy of the script executes, decided by the workflow YAML, not from extra comparison logic inside the evaluator. This does not fix arbitrary edits to the workflow file itself (a `pull_request`-triggered check on a same-repo branch runs using the PR's modified workflow — a general GitHub Actions limitation). The actual backstop for that is CODEOWNERS-enforced review on the governance-asset paths, which `generate` prints but cannot enforce (branch protection is a repo-admin action).

## `denied_commands` — explicitly scoped

Matching is word-tokenized prefix matching: `terraform apply` matches `terraform apply -auto-approve` but not `terraform -chdir=x apply` (different token at that position) or `terraform_apply_wrapper` (different token entirely). It does not catch aliases, variable expansion, or split flags (`rm -r -f` vs `rm -rf`). This is a documented, intentional limitation — a deterrent against unintentional dangerous commands, not a boundary against a determined actor with push access.

## Audit logging

Written synchronously inside the same invocation that makes the decision — `postToolUse` cannot log a denial on either platform, because a denied call never executes, so neither platform's completion event fires for it. The log (`.ai-governance/audit.log`) is `chmod 600` and gitignored by `generate` — it can contain command text and paths that may carry secrets, so it must never be committed. On the Copilot cloud-agent sandbox, this log is destroyed with the sandbox at job end; it is local, non-durable evidence, not fleet-wide audit — that's Phase 4.

## Boundaries with other commands

- `/platform-skills:setup-agents` scaffolds AI tool *config* (AGENTS.md, tool roster). `/platform-skills:ai-governance` scaffolds what those tools are *allowed to do*. Different concern, same repo-scan approach reused, not reimplemented.
- `/platform-skills:opa` is infra/Kubernetes policy-as-code (Rego/Conftest). `/platform-skills:ai-governance` is agent-behavior policy (a bash evaluator against tool calls and diffs). Two different policy engines — do not conflate them.
- `/platform-skills:zizmor` audits workflow *files* for security findings. `/platform-skills:ai-governance` audits agent *actions* taken through those workflows' AI tooling.
- `/platform-skills:pr-review`'s six review dimensions (cost, drift, ownership, compliance, upgrade, rollback) don't cover AI-authorship policy — that's this command's merge-time check, a narrower, separate concern.

## Roadmap

Phase 1 (this doc) has zero infrastructure dependency. Phase 2 (immutable, signed CI verifier), Phase 3 (centrally-distributed policy bundles), and Phase 4 (durable audit ingestion) are separate specs under `docs/superpowers/specs/` — each is optional, and none changes Phase 1's behavior when adopted.
