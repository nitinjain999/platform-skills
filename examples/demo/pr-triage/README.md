# Demo: PR Triage

> Status: Stable

A PR with three open review threads — one actionable fix, one informational, one not applicable.
The `/platform-skills:triage --all` command classifies each, applies the fix where justified, replies on every thread, and resolves only the threads that are eligible for closure.

## The scenario

PR #42 adds a new `payment-api` Deployment. Three reviewer comments are open:

| Comment | Classification | Action |
|---|---|---|
| "Missing `securityContext` — container runs as root" | `ACTIONABLE_FIX` | Adds pod + container securityContext, commits, publishes, resolves thread |
| "Consider adding a PodDisruptionBudget for HA" | `INFORMATIONAL` | Replies explaining the trade-off; thread left open — informational findings aren't resolved automatically |
| "Why not use Knative here?" | `NOT_APPLICABLE` | Replies that Knative is out of scope, resolves thread since the explanation isn't disputed |

## How to run

```bash
# Triage all open threads on PR 42
/platform-skills:triage --all 42

# Triage a single comment
/platform-skills:triage 42 <comment-id>

# Get comment IDs
gh api repos/nitinjain999/platform-skills/pulls/42/comments --jq '.[].id'
```

## What happens under the hood

1. Fetches all unresolved review threads via the triage helper's snapshot
2. For each thread: reads the comment, fetches the diff context, classifies
3. `ACTIONABLE_FIX` — reads the file in an isolated worktree, applies the minimal fix, validates, commits, and pushes; the fix commit runs the normal CI, it is never marked `[skip ci]`
4. Posts a reply on every thread explaining the classification and action taken
5. Resolves a thread only if the finding is eligible for closure: `ACTIONABLE_FIX` after successful remediation, `ALREADY_FIXED` with current evidence, or a verified `DUPLICATE`. `INFORMATIONAL`, `NEEDS_CLARIFICATION`, `OUT_OF_SCOPE`, and disputed `NOT_APPLICABLE` findings stay open, and a thread with any unresolved substantive concern stays open

## Files in this demo

- `deployment.yaml` — the original file with missing securityContext (what the PR adds)
- `deployment-fixed.yaml` — the file after triage applies the actionable fix

## Try it yourself

```text
Use $platform-skills to triage all open review comments on this PR.
Classify each finding. Apply safe, justified fixes only. Reply on every
thread. Resolve a thread only when the finding is actually eligible for
closure — leave informational, disputed, or out-of-scope threads open.
```
