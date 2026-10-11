# Plugin evals

Status: Beta

Behavioural evals for this plugin, run with [`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals). Each case is a realistic prompt plus graders that check what Claude produced with the plugin loaded, and, in the full run, the same prompt without the plugin, so the difference (`Δ`) shows what the plugin contributes.

`evals/` holds the older weighted-checklist suite and the token-optimizer benchmark. This suite lives in `plugin-evals/` and is registered in `.claude-plugin/plugin.json` under `experimental.evals`.

## Cases

| Case | Tag | Ported from | Graders |
|---|---|---|---|
| `flux-helmrelease` | `fluxcd` | `evals/flux-helmrelease` | 6 regex (checklist weights 2,2,2,2,1,1) + skill fired |
| `opa-policy` | `opa` | `evals/opa-policy` | 8 regex (checklist weights split where one item had two conditions) + skill fired |
| `pr-triage` | `triage` | `evals/pr-triage` | 8 regex (both scenarios) + skill fired |

Every grader is free (`regex` or `tool_used`), so a run costs only the agent calls. Each case also has a `tool_used: Skill` grader: a correct answer that did not come from the plugin is a finding, not a pass.

## What the baseline shows

First full run (2026-10-11, Claude Code 2.1.286, 2 runs per arm): every case scores 1.0 with the plugin, but the no-plugin baseline scores almost as well on two of them: `Δ` is +0.22 for `opa-policy`, +0.03 for `pr-triage` and +0.00 for `flux-helmrelease`. The ported checklists mostly test knowledge a capable model already has. Two follow-ups:

- Add cases that need this plugin's specific guidance (for example the triage helper's state model, or Flux layering rules this repository chose), so `Δ` measures something.
- On `pr-triage` the skill-fired grader failed in a single-arm run (no skill or command was invoked). That is a trigger-description finding for the commands-to-skills migration.

## Run it

Every run is a billed model call on your own credential.

```bash
# Only the domains this branch touched (what a PR gate would run): 1 run, no baseline arm
bash tests/plugin-evals.sh --changed origin/main

# Everything, with the no-plugin baseline (what a nightly job would run)
bash tests/plugin-evals.sh --all

# See what would run without calling a model
bash tests/plugin-evals.sh --changed origin/main --dry-run
```

`tests/plugin-evals.sh` fails when a case scores below the floor (0.7) or more than the tolerance (0.15) below its score in `baseline.json`. It does not gate on exact output: model answers vary, so scores are compared against a recorded baseline. Refresh the baseline deliberately after an intended change:

```bash
bash tests/plugin-evals.sh --all --runs 2 --update-baseline
```

`tests/plugin-evals-structure.sh` checks the suite's files without any model call (frontmatter keys, regex compilation, a skill-fired grader per case, tags the runner can select) and runs in CI.

## Adding a case

1. Create `plugin-evals/<case>/prompt.md` with a prompt a user would type, without naming the skill. Give it a `tags:` entry.
2. Add graders under `graders/`, one file each. Put regexes in the `pattern:` frontmatter key, use `flags: i` (inline `(?i)` is not supported), and keep notes as YAML comments.
3. Add the tag to `DOMAIN_MAP` in `tests/plugin-evals.sh` with the paths that should trigger it.
4. Run `bash tests/plugin-evals-structure.sh`, then the case itself, then refresh the baseline.

## CI status

Not wired into CI yet: the repository has no model credential. The runner is ready for it. A job needs `claude` installed, an `ANTHROPIC_API_KEY` secret (or cloud-provider credentials), and `bash tests/plugin-evals.sh --changed origin/${{ github.base_ref }} --model <pinned> --max-cost-usd <ceiling>`. Pin the model so a model rollout is not mistaken for a plugin regression.
