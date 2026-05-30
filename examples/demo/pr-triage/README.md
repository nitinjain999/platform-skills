# Demo: PR Triage

> Status: Stable

A PR with three open review threads — one actionable fix, one informational, one not applicable.
The `/platform-skills:triage --all` command classifies each, applies the fix, replies on every thread, and resolves them all in one pass.

## The scenario

PR #42 adds a new `payment-api` Deployment. Three reviewer comments are open:

| Comment | Classification | Action |
|---|---|---|
| "Missing `securityContext` — container runs as root" | `ACTIONABLE_FIX` | Adds pod + container securityContext, commits, resolves thread |
| "Consider adding a PodDisruptionBudget for HA" | `INFORMATIONAL` | Replies explaining the trade-off, resolves thread |
| "Why not use Knative here?" | `NOT_APPLICABLE` | Replies that Knative is out of scope, resolves thread |

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

1. Fetches all unresolved review threads via `gh` CLI
2. For each thread: reads the comment, fetches the diff context, classifies
3. `ACTIONABLE_FIX` — reads the file, applies the minimal fix, commits with `[skip ci]`
4. Posts a reply on every thread explaining the classification and action taken
5. Resolves every thread via GitHub GraphQL API

## Files in this demo

- `deployment.yaml` — the original file with missing securityContext (what the PR adds)
- `deployment-fixed.yaml` — the file after triage applies the actionable fix

## Try it yourself

```text
Use $platform-skills to triage all open review comments on this PR.
Classify each as ACTIONABLE_FIX, INFORMATIONAL, or NOT_APPLICABLE.
Apply safe fixes only. Reply on every thread. Resolve all threads.
```
