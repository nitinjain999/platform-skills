# Review Mode — Scoring Rubric + Output Options

## Discover agent files

```bash
ls .github/agents/*.agent.md 2>/dev/null
ls .cursor/rules/*.mdc 2>/dev/null
grep -l "## Agent Context" CLAUDE.md 2>/dev/null && echo "Claude Code agent sections in CLAUDE.md"
cat AGENTS.md 2>/dev/null
```

## Score each agent on 6 dimensions

| Dimension | Pass | Fail signal |
|-----------|------|-------------|
| Ownership clarity | Explicit boundaries, no overlap | "handles general concerns" |
| Knowledge specificity | ≥3 real paths from THIS repo | "follow project conventions" |
| Boundaries completeness | Off-limits + handoffs both present | Missing either |
| Autonomy calibration | Level fits agent's risk profile | infra agent on autopilot |
| Handoff completeness | "hand off to X when Y" present | Agent silently halts at boundary |
| **Staleness** | Paths exist, versions match deps, deploy process current | Dead paths, old versions |

**Staleness is the most silent failure.** A 6-month-old agent describing a Heroku deploy when the team moved to EKS actively misleads the model — it's worse than no agent file.

## Staleness check procedure

For each agent file, extract paths and check them:

```bash
for agent in .github/agents/*.agent.md .cursor/rules/*.mdc; do
  [ -f "$agent" ] || continue
  echo "=== $agent ==="
  # Pre-filter: remove URL lines before extracting tokens.
  # grep -o strips the scheme, so post-extraction URL filtering misses github.com/foo.md.
  # Use -E for portable extended-regex on both GNU and BSD grep.
  AGENT_LINES=$(grep -vE 'https?://' "$agent")
  # File references (allow leading dot for dotfiles like .github/workflows/ci.yml)
  echo "$AGENT_LINES" \
    | grep -oE '\.?[a-zA-Z][a-zA-Z0-9_/-]+\.(py|ts|go|tf|yaml|yml|json|md)' \
    | grep -vE '^example\.' | grep -vE '\.example\.' \
    | while read -r p; do
        test -f "$p" && echo "  ✓ $p" || echo "  ✗ $p MISSING"
      done
  # Directory references (trailing-slash paths like src/, tests/, .github/workflows/)
  echo "$AGENT_LINES" \
    | grep -oE '\.?[a-zA-Z][a-zA-Z0-9_./-]+/' \
    | grep -vE '^example\.' | grep -vE '\.example\.' \
    | sort -u \
    | while read -r d; do
        test -d "${d%/}" && echo "  ✓ $d" || echo "  ✗ $d MISSING"
      done
done
```

> **CLAUDE.md agent sections:** The staleness loop above covers `.agent.md` and `.mdc` files. `CLAUDE.md` Agent Context sections use a table format that doesn't embed file paths the same way — path-checking them is not straightforward. Note in the review report whether Claude Code sections exist and flag them for manual review if the repo has changed significantly.

## Example report format

```
coordinator.agent.md
  ✅ Ownership, Knowledge, Autonomy, Handoff
  ⚠️  Staleness — references src/api.py which no longer exists

app.agent.md
  ❌ Knowledge specificity — "follow conventions" is generic; no paths referenced
  ✅ Ownership, Boundaries, Autonomy, Handoff, Staleness

Priority improvements:
  1. app agent — add actual file paths and conventions (HIGH)
  2. coordinator — update src/api.py reference (LOW)

Run /platform-skills:setup-agents upgrade to apply.
```

## Output options (ask at end of review)

```
Save this report?
  1. .github/agents/agent-review.md — commit to repo, shareable with team
  2. GitHub PR comment markdown — formatted for gh pr comment
  3. No — chat output is enough
```
