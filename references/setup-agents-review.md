---
title: "Setup Agents: Review"
custom_edit_url: null
---

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

Extract only backtick-quoted tokens — real path references in agent prompts live in backticks. Prose mentions of filenames (e.g. "see package.json") are not checked because they are not actionable references and produce false positives in CI.

```bash
for agent in .github/agents/*.agent.md .cursor/rules/*.mdc; do
  [ -f "$agent" ] || continue
  echo "=== $agent ==="
  # Strip fenced code blocks and URLs, then extract backtick-quoted tokens only.
  BACKTICK_REFS=$(awk '/^```/{skip=!skip; next} !skip{print}' "$agent" \
    | grep -vE 'https?://' \
    | grep -oE '`[^`]+`' | tr -d '`')
  # File paths: must contain a / to exclude bare filenames from prose
  echo "$BACKTICK_REFS" \
    | grep -oE '[a-zA-Z0-9_./-]*(/[a-zA-Z0-9_.@-]+)+\.(py|ts|go|tf|yaml|yml|json|md|sh|kt|kts|rs|cs|rb|php)' \
    | grep -vE '<[a-zA-Z]' \
    | while read -r p; do
        test -f "$p" && echo "  ✓ $p" || echo "  ✗ $p MISSING"
      done
  # Directory paths: trailing slash; single segment like src/ is valid
  echo "$BACKTICK_REFS" \
    | grep -oE '[a-zA-Z][a-zA-Z0-9_.-]*(/[a-zA-Z0-9_.-]*)/' \
    | grep -vE '<[a-zA-Z]' \
    | sort -u \
    | while read -r d; do
        test -d "${d%/}" && echo "  ✓ $d" || echo "  ✗ $d MISSING"
      done
done
```

> **CLAUDE.md agent sections:** The staleness loop above covers `.agent.md` and `.mdc` files. `CLAUDE.md` Agent Context sections use a table format that doesn't embed file paths the same way — note in the review report whether Claude Code sections exist and flag them for manual review if the repo has changed significantly.

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
```

> **Fix path:** `upgrade` is git-diff-driven — it only patches agents whose files changed in git since the last update date. A generic-but-unchanged agent is invisible to upgrade. Use the options below to choose the right next step.

**At end of review, ask:**
```
How would you like to address the findings?

  1. upgrade — I've changed files since agents were last written; use git-diff to patch what's stale
  2. fix-specific — apply the review findings directly now (I'll edit each flagged agent)
  3. save-report — write findings to .github/agents/agent-review.md and decide later
  4. skip — chat output is enough
```

- Option 1 → run `/platform-skills:setup-agents upgrade`
- Option 2 → for each HIGH/CRITICAL finding: show the current `## How to work here` section, propose the minimal edit, ask to apply
- Option 3 → write the report (see Output options below), then suggest option 1 or 2 as follow-up

## Output options

```
Save this report?
  1. .github/agents/agent-review.md — commit to repo, shareable with team
  2. GitHub PR comment markdown — formatted for gh pr comment
  3. No — chat output is enough
```
