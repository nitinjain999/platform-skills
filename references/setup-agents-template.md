---
title: "Setup Agents: Template"
custom_edit_url: null
---

# AGENTS.md Template

> **Use `assets/AGENTS.md.template` as the canonical source.** Render it with `assets/render.sh` — do not regenerate the structure verbatim from this file. This page documents the sections and their intent; the asset file is what gets written to the target repo.

```bash
bash assets/render.sh assets/AGENTS.md.template \
  REPO_DESCRIPTION="One sentence. What this is. Who depends on it." \
  STACK_DESCRIPTION="Runtime, framework, deploy target." \
  WORKFLOW_DESCRIPTION="Deploy process, review gates, environments." \
  OFF_LIMITS="Paths no agent touches without explicit human instruction." \
  COORDINATOR_ROLE="coordinator" \
  ROSTER_ROWS="| app | src/, tests/ | release (deploys), reviewer (pre-merge) |" \
  CONVENTIONS="Naming, formatting, commit message format." \
  DATE="YYYY-MM-DD" \
  Q1_ANSWER="<verbatim answer to last-change-shipped question>" \
  OFF_LIMITS_ANSWER="<verbatim answer to never-want-agent-to-do question>" \
  PAIN_POINTS="  - \"<from interview>\"" \
  MODELS="  coordinator: <model-id>"
```

## Section intent (for reference)

| Section | Purpose |
|---------|---------|
| `## How to invoke agents` | Always include — developers don't know @mentions exist |
| `## Repo` | One sentence — what this is and who depends on it |
| `## Stack` | Runtime, framework, deploy target — one line each |
| `## How we work` | Deploy process in plain English, review gates, environments |
| `## Off-limits` | Paths no agent touches without explicit human instruction |
| `## Agent roster` | Table: agent → owned paths → handoff targets |
| `## Conventions` | Naming, formatting, commit message format |
| metadata block | Machine-readable — read by upgrade and add modes |

## Metadata block

Always use YAML literal block scalars (`|`) for `q1` and `off-limits` — the developer's answer will contain colons, punctuation, and special characters that corrupt inline YAML strings.

```
<!-- setup-agents metadata
generated: YYYY-MM-DD
q1: |
  <verbatim answer — safe to contain colons, quotes, backticks>
off-limits: |
  <verbatim answer>
pain-points:
  - "<from interview>"
models:
  coordinator: <chosen model-id>
  app: <chosen model-id>
-->
```

Read with: `sed -n '/<!-- setup-agents metadata/,/-->/p' AGENTS.md`
