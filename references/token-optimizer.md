# Token Optimizer

Deep reference for `/platform-skills:token-optimizer`. Read `commands/token-optimizer.md` first for the wizard; this covers the mechanics behind it.

## Config schema

```yaml
version: 1

enabled: true          # false short-circuits before any classification; default: true
mode: audit            # off | advisory | audit | redirect; default: audit

worker_agent: platform-bulk-reader
worker_model: claude-haiku-4.5   # request only — verified on Copilot CLI 1.0.59: claude-haiku-4.5, gpt-5-mini, gpt-5.4-mini; only the VS Code coordinator pins a model, claude-sonnet-4.6

max_lines: 350         # absolute gate on every read, ranged or not
max_bytes: 32768       # absolute gate on every read, ranged or not
max_range_ratio: 80    # percent threshold for reporting whole-file reads (reporting only)

default_read_limit: 0  # 0 = unknown, treat omitted limit as whole-file; 2000 auto-applied on Claude Code

summary_words: 600     # instruction-level request to worker, not an enforceable cap

cumulative_lines: 8000      # advisory signal, never denies
cumulative_bytes: 524288    # advisory signal, never denies

max_delegations_per_task: 3   # instruction-only where client does not enforce natively
max_worker_retries: 1         # instruction-only where client does not enforce natively
max_worker_seconds: 120       # instruction-only where client does not enforce natively

exempt_agent_types:
  - platform-bulk-reader

log: .token-optimizer/decisions.log
state_dir: .token-optimizer/state
```

**All thresholds are starting hypotheses from the design, not measured optima.** They ship conservative and are meant to be tuned per repository after observing real workload patterns.

Invalid values are rejected and the default retained, with a degradation line logged. An invalid threshold silently applied is worse than a default: `max_lines: -1` would make every one-line read oversized.

## Verified capability matrix

Probed 2026-09-10. These versions change frequently and must be re-probed against your own installations before relying on any row.

| Client | Version probed | Delegation | Read redirection | Notes |
|---|---|---|---|---|
| Claude Code | 2.1.236 | Probe shipped, **not yet run** | Yes, once probe passes | `agent_type` documented on `PreToolUse` — reader can be exempted reliably |
| Copilot CLI | 1.0.59 | **Unverified** | No | Documented `preToolUse` payload carries no per-call worker identity |
| Copilot in VS Code | 1.137.0 | **Unverified** | Conditional | Agent-scoped hooks preview, gated on `chat.useCustomAgentHooks` |

Claude Code is the only client where redirection is architecturally possible. Even there, `doctor` reports `delegation verified: no` until you run `.token-optimizer/probe/run-probe.sh` on your own machine. The shipped fixture is deliberately un-run because it requires a live session and a human reading a transcript.

### The `/fleet` vs `/agent` finding

`copilot help commands` lists subagent execution under:
- `/fleet` — parallel subagent execution
- `/tasks` — subagents and shell commands

`/agent` sits under "Agent Environment" and is described as *browse and select from available agents*. This is a session transition, not a dispatch that returns, and a transition saves no parent context.

`handoffs` appears in the Copilot templates as a frontmatter field but is **not** confirmed to be a subagent dispatch. Presence of a field means the field parses, not that an execution model exists. No delegation primitive is verified as working on Copilot CLI or VS Code until a runtime fixture runs and a human confirms the answer-key path list appeared in the parent's context.

Read "unverified" strictly: not demonstrated, not proven absent. GitHub documents an `agent` tool alias, and its absence from a particular CLI build's `--help` output is not evidence that delegation cannot work — tool availability has to be checked against the installed client version and the official documentation. `handoffs` does not settle it in the other direction either, since it does not demonstrate a separate worker context or a return to the parent. Both remain open, which is why no delegation or saving is claimed for these clients.

## The capability probe gate

Three questions determine whether a client can reach `redirect` mode:

1. **Does the client's documented payload include a per-call worker identity?** Without it, the core cannot exempt the configured reader agent reliably — the worker would be denied when it tried to read what it was asked to read, deadlocking the delegation.

2. **Does the client support delegation?** The worker must be able to return a bounded answer to the parent, which must resume with that answer in its context.

3. **Did the delegation probe succeed in a real session?** The shipped probe is deliberately un-run. A passing test is not the same as a working feature.

Questions 1 and 2 cannot be automated. They require reading vendor docs, probing API shapes, and running a fixture in a live session where a human reads the transcript to confirm the parent received the worker's path list. The version-invalidation rule: any client update that touches hooks, agent APIs, or payload shapes invalidates all three answers and requires re-verification.

## The four modes

| Mode | Behavior |
|------|----------|
| `off` | No classification at all. Short-circuits before reading the payload. |
| `advisory` | Classification runs and cumulative counter updates, but the payload is still read and parsed first, so a malformed payload can still produce a single degradation line. No per-read decision is logged and nothing is emitted on success. Use this to measure cumulative discovery patterns without logging individual opportunities. |
| `audit` | Classification runs, cumulative counter updates, and oversized reads are logged as `would_redirect`. Denies nothing. Default. |
| `redirect` | Denies oversized reads with a JSON deny envelope carrying the reason, worker name, seven-part contract, worker budgets, and file path. Real platforms (claude, copilot, vscode) exit 0; platform=none exits 2 (scriptable dry-run signal). Shell reads are audit-only on every client and in every mode. |

`enabled: false` short-circuits before any other check, so `enabled: false` plus `mode: redirect` still emits nothing and exits 0.

### What a developer sees under each mode

**`off`**: nothing interrupts, no classification runs, and no per-read decision is logged. The payload is still read and parsed, so a malformed payload can still write a single `degraded / optimizer_unavailable / payload parse failed` line to the log. An "off" optimizer is not silent on invalid input.

**`advisory`**: nothing interrupts. Reads proceed normally. The log shows only cumulative threshold crossings (`cumulative_exceeded`), never individual per-read opportunities. Use this to measure session-wide discovery cost without the noise of every single read.

**`audit`**: nothing interrupts. The log accumulates `would_redirect` lines showing individual redirection opportunities, plus cumulative threshold crossings. Use this to measure workload patterns before switching enforcement on.

**`redirect`**: a large-file read is denied with a message like:

> This read is large enough to be worth delegating. Ask the platform-bulk-reader subagent to answer the specific question against references/aws-waf.md and return bounded evidence: a complete|partial|blocked verdict, file paths and symbols, short excerpts, the exact file paths its answer rests on so you can hash them yourself before editing, what was omitted or truncated, and remaining uncertainties, in roughly 600 words. Budget: at most 3 delegations for this task, 1 retries, 120 seconds. Then read only the sections you must verify yourself.

The parent must delegate. The second attempt on the same file passes — bounded recovery ensures the parent can always read primary evidence directly after the worker has run.

### Platform capability caps

Platform capability CAPS the configured mode. A repo that shares one config across clients must not redirect on a client that cannot support it.

| Platform | Config says `off` | Config says `advisory` | Config says `audit` | Config says `redirect` |
|---|---|---|---|---|
| Claude Code | off | advisory | audit | redirect |
| Copilot CLI | off | advisory | audit | **audit** |
| VS Code | off | advisory | audit | **audit** |

Copilot CLI is capped at `audit` even when the config says `redirect` because the documented `preToolUse` payload carries no per-call worker identity, so the reader cannot be reliably exempted. VS Code is capped for the same reason plus delegation unverified.

**Probe status is reported by `doctor` and not enforced by the core.** Running delegation-probe verification on the hot path of every tool call, for a cost feature, is the wrong trade. Bounded recovery already handles a delegation that does not work: the first oversized read is denied once, and if the model cannot actually delegate, the second attempt on that file proceeds. The core trusts that you ran `doctor` before switching to `redirect` mode.

Run `optimize.sh --mode=explain` to see the effective mode and the cap reason, if any:

```
effective mode:       audit  [capped to audit: redirection unsupported on copilot (no per-call worker identity in the documented payload)]
```

## Why pass emits nothing

On pass the core emits NO JSON and never `permissionDecision: "allow"`. An explicit allow could contend with an `ai-governance` deny registered on the same `PreToolUse` event. Multiple hooks compose: the first to deny wins, and an explicit allow from a different hook has no authority to override that.

A read that does not meet the size threshold simply exits 0 with no output. The client sees silence and allows the call to proceed.

## Why this fails open while `ai-governance` fails closed

`optimize.sh` fails **open** on every error path. Any parse failure, missing dependency, invalid config, or state-write failure logs one degradation line, emits nothing, and exits 0. The read proceeds.

`examples/ai-governance/evaluate.sh` fails **closed**. A missing `yq`, invalid YAML, or type error in the policy file emits `policy_load_failed` and exits 2.

**Both directions are correct for what they are.** A security gate that silently stops gating when its own config breaks is worse than a broken session — denying reads is strictly worse than allowing them, so a governance feature that stops enforcing the moment it fails becomes invisible until something it should have blocked actually ships.

A cost optimizer that starts denying reads when its own config or state management breaks gets uninstalled by lunchtime. The optimizer's job is to route some reads to a cheaper model. Routing zero reads because the core is degraded is the same outcome as routing zero reads because it was never installed, except developers now have an unexpected denial to debug. Failing open preserves session usability while logging the exact degradation so you can fix the config.

The two scripts look similar. They are not interchangeable. Do not "fix" the asymmetry — `ai-governance` must stay fail-closed, and `token-optimizer` must stay fail-open, for the reasons above.

## Size classification

`classify_size` applies three checks to every read request, ranged or not:

1. **Requested line count > `max_lines`** → oversized
2. **Requested byte count > `max_bytes`** → oversized (measured, never estimated)
3. **Range ratio > `max_range_ratio`** → reported as whole-file read (reporting only, never denies)

`max_lines` and `max_bytes` are **absolute gates**. A ranged read that asks for 500 lines is oversized even if the file is 100,000 lines and the range is 0.5% of it.

`max_range_ratio` is reporting-only. It flags reads that span more than that percentage of the file's total line count, so the log distinguishes "read 200 lines of a 210-line file" (whole-file cost) from "read 200 lines of a 50,000-line file" (targeted). This signal can never turn an over-limit request into a pass.

### Measured range bytes, not estimated

Range byte counts are **measured** by reading the range, never estimated from a per-line average. A five-line window can be 200 KiB if those lines are minified. An estimate would report it as tiny; measurement catches it.

### `awk NR` vs `wc -l`

Line counts use `awk 'END{print NR}'`, not `wc -l`. `wc` counts newlines, so a file whose final line is unterminated reports one short — and that invisible line can be 50 KiB. `awk NR` counts lines, so the unterminated line is visible and its byte count is included in classification.

### Client default read limits

An omitted read limit means the **client's default**, not the whole file. The core fills in 2000 automatically on Claude Code, whose `Read` tool defaults to 2000 lines. It is 0 (unknown) elsewhere until probed.

When `default_read_limit` is 0 and a read request omits `limit`, the core treats it as requesting the entire file. This is fail-safe: the unknown case assumes the worst-case cost.

### Two holes the design had

An earlier draft used total line count where requested line count was correct, and estimated range bytes from `total_bytes * (requested_lines / total_lines)`. Both shipped as bugs and were caught in review:

1. **Total lines > `max_lines` denied ranged reads that asked for 40 lines.** A 1000-line file would be classified oversized even when `--limit=40` explicitly requested a small window. The correct check is `requested_lines > max_lines`.

2. **Estimated range bytes missed fat-line files.** A file with five 40 KiB lines has 200 KiB in the first five lines, but `total_bytes * (5 / total_lines)` reports a tiny number. The fix is `sed -n` plus `wc -c` on the actual range: measure, never estimate.

## Shell detection limits

`detect_shell_full_read` recognises `cat`, `less`, `more`, `bat`, and `head`/`tail` with `-n` counts that exceed `max_lines`. The command string is **pattern matched only**, never executed, evaluated, or passed to a subshell.

**What is not recognised**: a pipe, `rg`, `awk`, a Python one-liner, or any other construct that can also print an entire file. These are deliberately not claimed as recognised. Unrecognised syntax is logged as `shell_unparsed`, which is an audit finding, not proof of safety.

**This is not a data boundary.** Shell-read detection is a cost heuristic. A developer with push access who wants to read a file via an unrecognised command can do so. The session logs the attempt as `shell_unparsed`, but the read proceeds. This is the correct behavior for a cost feature.

**Shell reads are audit-only in every mode.** Recognised oversized shell reads are logged as `would_redirect` even under `mode: redirect`. They never emit a deny envelope and never exit non-zero. Pattern matching is too weak to safely deny: `cat large-file` in the command string does not prove the whole file was read. Denying on a pattern match would block commands that may not have read the whole file at all.

## Bounded recovery

The core denies an oversized read **at most once per session per file**. The second attempt on the same target always passes. This prevents deadlock: the parent must retain a way to read large primary evidence directly, even after the worker has summarised it.

### The one-denial rule

On the first oversized read of a target, if state can be durably persisted:
- `record_redirect_attempt` writes the counter file
- If the write succeeds, the core emits the JSON deny envelope. Real clients (claude, copilot, vscode) exit 0 so the client consumes `permissionDecision` and the reason; only `--platform=none` exits 2, as its scriptable dry-run signal
- The second read of the same target sees `redirect_attempts >= 1` and passes

If the write fails:
- Log `recovery_unavailable` and pass immediately
- Do not deny

**Why persistence is required before denying**: without durable state, the counter never advances. The same read would be denied forever, deadlocking the parent. Bounded recovery exists to prevent exactly this. A session that cannot write state cannot enforce bounded recovery, so it must not deny at all.

### No shared session fallback

The state key is a hash of `session_id` plus the absolute file path. `session_id` is read from the payload first, then falls back to `TOKEN_OPTIMIZER_SESSION`, `CLAUDE_SESSION_ID`, or `COPILOT_SESSION_ID` env vars. There is **no shared literal default** like `"nosession"`.

Without a session identity, state cannot be scoped. A shared bucket would let one session inherit another's exemption: Session A hits the large file and is denied, Session B opens the same repo an hour later and passes on the first read because the state file already exists. That would be wrong.

An empty session ID means "no state possible". The core logs `recovery_unavailable / state_write_failed` and passes immediately, because it cannot bound the recovery.

### Keyed on session + absolute path

`state_key` is `hash(session_id + "|" + absolute_path)`, not a sanitised filename. Two different file paths that sanitise to the same string (e.g., `src/foo.tf` and `src-foo.tf` both becoming `src_foo_tf`) would share one state file. A hash is collision-resistant and does not flatten distinct paths.

## Recursion prevention

The configured `worker_agent` must be able to read what it was asked to read. `is_exempt_agent` checks the payload's `agent_type` field against the `exempt_agent_types` list and skips classification if matched.

**Exemption is per-client identity, not per session.** There is no session-wide "delegation in progress" flag, because the parent and worker have different `agent_type` values in their payloads. The parent is not exempt; the worker is. This is why the per-call worker identity matters: without it, the core cannot tell parent reads from worker reads, and exemption becomes all-or-nothing for the whole session.

**Exemption is scoped to the size threshold only.** A worker that writes to a protected path is still governed by `ai-governance`. The two hooks compose: `token-optimizer` exempts the worker's reads, `ai-governance` governs its writes.

## Reader contract

The worker returns a seven-part answer:

**1. Verdict** — one of `complete`, `partial`, `blocked`:

| Verdict | Use when |
|---|---|
| `complete` | Fully searched the stated scope. |
| `partial` | Searched but truncated, excluded, or ran out of budget. Name what was skipped. |
| `blocked` | Could not search meaningfully. Give the reason. |

State the verdict first, on its own line. "Searched everything, found nothing" and "gave up early" read identically in prose and mean opposite things. The parent needs to tell them apart before acting.

**2. Answer** — a direct answer to the question asked.

**3. Evidence** — file paths and symbol names. Line numbers only when the worker actually read that line; never inferred.

**4. Excerpts** — short, and only where one is needed to verify a finding.

**5. Scope** — what was searched, what was excluded, what was truncated.

**6. Paths for verification** — list the exact repository-relative path of every file the answer rests on, as a plain list.

**7. Uncertainties** — plus the next targeted sections worth inspecting.

### Why hashes matter

The worker lists paths; the **calling agent** hashes them. The worker has no shell and must never report a hash it did not compute. A worker-reported hash can be fabricated by the worker; one the caller computes cannot.

The parent hashes the listed paths before editing any of them. This is how it detects that evidence went stale between discovery and the change it informs — a real hazard when discovery is a separate turn from the edit.

### Worker budgets are instruction-level

`summary_words`, `max_delegations_per_task`, `max_worker_retries`, and `max_worker_seconds` are carried in the redirect reason as instructions to the model. Where the client does not enforce them natively, they are **instruction-only**. `doctor` reports which budgets are natively enforced. An unenforced budget that reads as enforced is how a cost feature becomes a cost problem.

## Cumulative discovery

A per-file threshold misses the real workload: many-small-reads discovery (reading 50 files, 100 lines each) has the same token cost as a single 5000-line read, but the per-file gate never triggers because no individual read is large.

`cumulative_add` tracks total lines and bytes read during a session. When the cumulative count exceeds `cumulative_lines` or `cumulative_bytes`, the core logs `cumulative_exceeded`.

**This is advisory on every client** and never denies. A session is not a task boundary. Denying the fortieth read of a long session because of the previous thirty-nine would be wrong: the session might span three unrelated tasks, and the third task's first read being denied because of unrelated earlier work would be confusing and incorrect.

The log line tells you the session's discovery cost is high. What to do about it is a human judgment call — possibly split the task, possibly accept the cost, possibly tune the threshold.

## Measurement

The benchmark harness (not included in this document) defines four mutually exclusive arms:

1. **Baseline** — no delegation, no read interception
2. **Concise** — `mode: advisory`, instructions only
3. **Delegated** — `mode: redirect`, actual worker dispatch
4. **Native** — the client's own built-in discovery agent, where one exists

Usage fields are **mutually exclusive per actor per billing unit**. Total task cost sums across all actors. An actor is the coordinator or a worker; a billing unit is one model invocation at one provider. Same model, different context window state (e.g., before and after cache warming) counts as one actor.

### Why retries are not a cost field

Retries are NOT a separate cost field. A retry produces its own token counts inside the actor that retried, so adding a `retries` field would double-count: you'd count the original attempt (which failed) and then add the retry's tokens again even though they're already in the actor's input/output/cache counts. Don't invent a retries field.

### Cache state

`cache_state` may be `cold`, `warm`, or `unknown`. On providers and models that do not support prompt caching, report `unknown`, not `cold`. A `cold` state means caching is available but the cache missed. `unknown` means you don't know if caching happened.

### Formulas

**Per actor**: `total_tokens = input_tokens + output_tokens + cache_creation_tokens`

**Per task**: `task_total = sum(each actor's total_tokens)`

Cache read tokens are free or discounted depending on the provider, but they still load context and consume time. Track them separately as `cache_read_tokens` if your provider exposes them; otherwise note `cache_state` and accept that the read component is not directly measured.

### Answer-key isolation

The acceptance criteria (≥25% median total reduction on eligible large-discovery tasks, <20% latency regression on small-task controls, no observed correctness regression across the runs performed, zero critical seeded findings lost) are **goals**, explicitly not measured in this repository.

Three runs per arm cannot establish the absence of a regression. Any published result must state the run count beside the claim. No savings figure is published in v1.41.0.

## Copilot BYOK

Copilot's BYOK variables — `COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_API_KEY`, etc. — are launch-time and session-wide. They cannot scope a cheap provider to one worker while keeping the coordinator on the expensive provider.

This means BYOK is a **whole-session option only**. Routing all agents to the cheap provider may work if that provider supports the coordinator model too, but mixed routing (cheap workers, expensive coordinator) is not architecturally possible with environment variables that are read once at launch.

## Boundaries with other commands

**vs `/platform-skills:ai-governance`**: governance is "what tools are allowed to do" (protected paths, denied commands, disclosure). Token optimizer is "route some reads to a cheaper model". Governance blocks or logs violations; the optimizer delegates and logs opportunities. They compose: a worker exempted from size classification is still governed on write intent.

**vs `/platform-skills:setup-agents`**: `/platform-skills:setup-agents` scaffolds which AI tools a repo uses and what their agent rosters contain. This command adds one worker to an existing roster and decides which model does the reading. Neither verifies the other's behaviour, and they share no probe infrastructure: delegation verification for this feature is copied into `.token-optimizer/probe/run-probe.sh` during setup, and a human runs it against a live session.

**vs `/platform-skills:self-improve`**: self-improve runs behavioural tests and promotes corrections to session memory. Token-optimizer's 59-test suite (`examples/token-optimizer/tests/optimize_test.sh`) is an input to self-improve when the optimizer's behavior changes. Different concerns, same test-driven approach.

## Roadmap

Four deferred items, each optional and non-breaking:

1. **Answer-key benchmark runs** — the harness is runnable, but no results are published in v1.41.0. Running it requires provider credentials, coordinator and worker sessions, and controlled task selection. Results would state the run count, task characteristics, and which correctness claims are tested vs assumed.

2. **Adaptive threshold tuning** — use the cumulative log to recommend per-repo `max_lines`/`max_bytes` instead of shipping one set of conservative defaults. A repo whose reads are consistently 50 lines or 10,000 lines has different optimal thresholds.

3. **Cross-session aggregation** — a report mode that aggregates decision logs across a team or timespan, showing delegation rate, cumulative discovery events, and clients used. Currently `report` mode summarises one log; cross-session requires a log ingestion pipeline.

4. **Integration with external cost tracking** — emit structured events (not just log lines) that a billing reconciliation system can ingest. Currently the log is human-readable; a billing system would need to parse it or receive a separate event stream.

All four are deferred because they require infrastructure (controlled benchmark runs, aggregation storage, billing system hooks) or measured data (adaptive tuning) that are not present in the initial release. None changes the core's behavior; each extends observability or tuning.
