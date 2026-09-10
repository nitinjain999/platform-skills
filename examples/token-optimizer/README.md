# Token Optimizer Examples

Status: Beta

Templates for `/platform-skills:token-optimizer`. The command copies these into a target repo; nothing here is active until you run `setup`.

## What is here

| Path | Purpose |
|---|---|
| `optimize.sh` | Policy core. Classifies requested read size and emits pass / audit / redirect. |
| `token-optimizer.yaml` | Sample config. Copy to the repo root as `.token-optimizer.yaml`. |
| `tests/optimize_test.sh` | Behavioural suite. Run directly; no client session needed. |
| `claude/` | Reader agent, settings snippet, and the delegation probe. |
| `copilot-cli/` | Reader plus coordinator, delegation unverified, audit-only hook. |
| `vscode/` | Reader plus coordinator, with model-resolution and preview caveats. |

## Support by client

Probed 2026-09-10. Re-verify against your own client versions before relying on any row.

| Client | Version probed | Delegation | Read redirection |
|---|---|---|---|
| Claude Code | 2.1.236 | Probe shipped, **not yet run** | Yes, once the probe passes — `agent_type` is documented on `PreToolUse`, so the reader can be exempted reliably |
| Copilot CLI | 1.0.59 | **Unverified** — runtime fixture required | No — the documented `preToolUse` payload carries no per-call worker identity |
| Copilot in VS Code | 1.137.0 | **Unverified** — runtime fixture required | Conditional — agent-scoped hooks are preview, gated on `chat.useCustomAgentHooks` |

Claude Code is the only client where redirection is architecturally possible, and even there `doctor` reports `delegation verified: no` until you run `claude/probe/run-probe.sh` on your own machine. The shipped fixture is deliberately un-run.

`handoffs` appears in the Copilot templates but is **not** confirmed to be a subagent dispatch. `copilot help commands` lists subagent execution as `/fleet` and `/tasks`; `/agent` is "browse and select from available agents", a session transition that saves no parent context. Presence of a frontmatter field means the field parses, not that an execution model exists.

## Three things this is not

**Not a data boundary.** Whole-file shell-read detection is pattern matching. A pipe, `rg`, awk, or a Python one-liner can print an entire file and is not recognised. Unrecognised syntax is logged as an audit finding, never treated as safe.

**Not a spend limit.** A local read hook cannot impose a financial ceiling. Use your vendor's budget controls. This reports and recommends.

**Not measured.** No savings figure is published. The benchmark harness ships runnable so you can produce your own numbers; the design's targets are acceptance goals, not results.

## Failure direction

`optimize.sh` fails **open**. Any error logs one degradation line, emits nothing, and exits 0.

This is the opposite of `examples/ai-governance/evaluate.sh`, which fails **closed**. Both are correct for what they are: a security gate that silently stops gating is worse than a broken session, while a cost optimizer that starts denying reads when its own config breaks gets uninstalled by lunchtime. The two scripts look similar. They are not interchangeable.

## Try it without installing anything

```bash
cd examples/token-optimizer

# Classify a file directly
bash optimize.sh --mode=classify --path=../../references/aws-waf.md --config=token-optimizer.yaml
# -> oversized

# See exactly why, and what the decision would be
bash optimize.sh --mode=explain --platform=claude \
  --path=../../references/aws-waf.md --config=token-optimizer.yaml

# Watch the platform cap take effect: same config, different client
bash optimize.sh --mode=explain --platform=copilot \
  --path=../../references/aws-waf.md --config=token-optimizer.yaml

# Run the behavioural suite
bash tests/optimize_test.sh
```

The sample config ships `mode: audit`, so a hook run against it **emits nothing** and exits 0 — that is the point of the default. Use `explain` to see the decision without needing output from the hook, and `--platform=none` for a vendor-neutral rule line that writes no log and no recovery state.
