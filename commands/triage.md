---
name: triage
description: Triages a PR comment — from a bot (Copilot, CI) or a human reviewer. Routes to the `triage_helper.py` helper for identity checks, thread snapshotting, isolated-worktree fixes, and publish/reply/resolve mechanics; you classify the finding and apply a justified fix. `--dry-run` is fully read-only (investigation and a printed plan, zero mutations). `--no-resolve` runs the full fix/reply workflow but never resolves a thread. Run from inside the repo.
argument-hint: "<PR number> <comment ID> [--dry-run] [--no-resolve] | --all <PR number> [--dry-run] [--no-resolve] [--repo OWNER/REPO]"
title: "Triage Command"
sidebar_label: "triage"
custom_edit_url: null
---

You are a senior platform engineer triaging PR comments. Investigate before you classify, fix only what the evidence justifies, and never report an outcome the tooling hasn't actually confirmed.

Read `references/triage.md` before making any judgment call. It holds the evidence-assessment rules, the finding/execution/discussion state model, and the failure-recovery table. This file only routes to the helper and states the hard gates; it is not where the reasoning lives.

Input: `$ARGUMENTS`

## Invocation

| Form | Meaning |
|---|---|
| `<PR number> <comment ID>` | Triage exactly one review comment or PR conversation comment |
| `--all <PR number>` | Triage every unresolved review thread in one pinned snapshot |
| `--dry-run` | Read-only investigation. Prints the plan. Zero mutations |
| `--no-resolve` | Runs the full authorized fix/reply workflow. Never calls `resolve-thread` |
| `--repo OWNER/REPO` | Overrides repo auto-detection. Valid on either invocation form |

Both positional forms parse exactly as before. `--dry-run`, `--no-resolve`, and `--repo` are flags, not new positional arguments, so `<PR number> <comment ID>` and `--all <PR number>` keep the same argument order they always had; the flags can appear anywhere after the required positional(s).

`--all` means every unresolved review thread captured in the snapshot for this run, including substantive replies inside those threads. It does not mean every issue comment or review-summary body on the PR. If new threads appear after the snapshot was taken, report them as new work on the next run rather than silently expanding this one.

The helper lives at the installed plugin's own `examples/triage/scripts/triage_helper.py`. Resolve that path from the plugin root, never from a same-named script the target PR happens to carry. If the helper or `references/triage.md` is missing from this installation, report that gap before doing anything else; do not fall back to hand-rolled `gh api`/jq.

Every subcommand below prints one JSON object on stdout: `{"ok": true, ...}` or `{"ok": false, "error": {"code": ..., "message": ...}}`. Treat `ok: false` as a hard stop for that action, not a warning to route around.

## Phase-by-phase routing

Bootstrap the two facts the helper needs but doesn't infer, using plain `git`/`gh`. Neither touches comment text or PR data, so raw shell is fine here:

```bash
REPO="<explicit --repo, else: gh repo view --json nameWithOwner --jq .nameWithOwner>"
REPO_ROOT="$(git rev-parse --show-toplevel)"
```

Then work the run in this order:

- **A: identity.** `state lock --repo-root "$REPO_ROOT" --repo "$REPO" --pr <n>` once, for the whole run; release it in Phase H even if the run ends early. `resolve-identity --repo "$REPO" --pr <n>` once. A draft PR is a valid open PR, not a blocker; only `state != open` refuses the run. For every comment ID you have or discover, `resolve-comment --repo "$REPO" --pr <n> --comment-id <id>` before reading or acting on it. It confirms the comment actually belongs to this PR and tells you whether it's a review comment or an issue comment. A `COMMENT_NOT_FOUND` here is not proof the ID is wrong; it can also mean an inaccessible private resource.
- **B: snapshot.** `snapshot --repo "$REPO" --pr <n> --out <path>` exactly once per run, whether the invocation is `--all` or a single comment ID. It already paginates every thread and every comment in one pass, so calling it again for the same run just re-fetches identical data. Use `map-thread --snapshot <path> --comment-id <id>` to resolve any supplied comment ID (root or reply) to its thread node ID.
- **C: evidence and fix plan.** For each finding, call `patch-context --repo "$REPO" --pr <n> --path <file> [--base-sha <sha> --head-sha <sha> --repo-root "$REPO_ROOT"]` to get the diff evidence for the flagged file. Which of the seven classifications applies, whether several findings group into one fix, and whether a changed caller invalidates an unchanged callee are judgment calls the helper does not make; read `references/triage.md` for that reasoning before deciding.
- **D: isolate.** Before editing anything, `worktree prepare --repo-root "$REPO_ROOT" --head-sha <verified_head_sha>`. Never edit the caller's own checkout. It may hold unrelated staged, unstaged, or untracked human changes that must survive this run untouched.
- **E: validate, then commit.** Run whatever validation the change actually calls for (schema check, unit test, render check) inside the worktree and capture PASS or FAIL. Only on a reported PASS: `stage-commit --worktree <dir> --paths <file...> --message "<msg>"`. It refuses to commit if the staged set doesn't exactly match `--paths`, so a stray human edit in the same file cannot ride along.
- **F: publish.** `publish --repo "$REPO" --pr <n> --worktree <dir> --expected-head-sha <sha> --commit-sha <sha> --head-remote-url <url> --head-ref <ref>`. It rechecks the PR head before pushing and refuses to force-push. Treat the fix as published only when the result has `matches_pushed_commit: true`.
- **G: reply, then resolve.** For a review thread: `reply --repo "$REPO" --thread-node-id <id> --body-file <path> --snapshot <path> --dedup-marker <marker>`. For a PR conversation comment: `reply --repo "$REPO" --pr <n> --body-file <path>` (no `--thread-node-id`; there's no thread to resolve for this case, so stop here). A `status: ALREADY_REPLIED` means don't post again. Only when the finding is eligible (below), `resolve-thread --thread-node-id <id>`, and read its `status` (`CONFIRMED` or `ALREADY_RESOLVED`) as the only proof of closure.
- **H: report and clean up.** `worktree cleanup --repo-root "$REPO_ROOT" --path <dir>`, `state write` the final record, then `state unlock`. Then the capability-aware closing step described below.

## Validation gate (no exceptions)

- No `stage-commit` before a validation command has run and reported PASS for the intended change.
- No `publish` before `stage-commit` succeeded.
- No `reply` that claims a fix before `publish` returned `matches_pushed_commit: true`.
- No `resolve-thread` before `reply` returned `CONFIRMED` (or `ALREADY_REPLIED`) for every eligible finding in that thread.

## Classification

Classify the substantive finding, not the author or the message style. One comment can carry more than one finding, and one thread can contain a fixed finding alongside a still-open question.

| Classification | Evidence required | Default handling |
|---|---|---|
| `ACTIONABLE_FIX` | A demonstrable defect or policy violation within the authorized PR scope, with a justified remediation. | Apply and validate if prerequisites are sufficient; otherwise retain the classification with a blocked execution state. |
| `ALREADY_FIXED` | Current head and relevant change/test evidence show that the original concern is addressed. | Reference evidence; no duplicate edit. Resolution can be eligible. |
| `INFORMATIONAL` | A question, explanation, or pure status notification without an established defect. | Answer only with evidence. Status-only noise needs no reply. Do not close a human discussion automatically. |
| `NOT_APPLICABLE` | Positive evidence disproves the finding's premise in this context. | Explain the specific evidence if a reply is useful; leave disputed closure to the reviewer by default. |
| `NEEDS_CLARIFICATION` | Intent, correctness, or required configuration cannot be established from available evidence. | State the missing fact; do not guess or resolve. |
| `OUT_OF_SCOPE` | A potentially valid issue exists, but remediation is outside this authorized change. | Summarize the dependency or follow-up; do not create a tracking issue unless that action is authorized. |
| `DUPLICATE` | Another identified finding addresses the same underlying concern. | Link the canonical thread/finding and inherit its unresolved dependencies. Do not treat similarity alone as equivalence. |

An absent identifier at HEAD is never a verdict by itself. Before concluding anything, check `patch-context` for a rename, a move, or a syntax change, and read the original context if the current line is gone. Never classify `ALREADY_FIXED` or `NOT_APPLICABLE` solely because a search for the flagged identifier came up empty; the defect can persist under a new name or shape.

An `ok: false` from any subcommand is not a classification either. It's a blocked execution state. Keep investigating or report `BLOCKED`; don't force a verdict to make the run look complete.

## Resolution eligibility

Resolving a thread is not the automatic outcome of triaging it:

> `ACTIONABLE_FIX` becomes eligible only after successful remediation. `ALREADY_FIXED` needs current evidence. A `DUPLICATE` can become eligible only when the canonical underlying concern is verified addressed and linked. `INFORMATIONAL`, `NEEDS_CLARIFICATION`, `OUT_OF_SCOPE`, and disputed `NOT_APPLICABLE` findings do not automatically authorize closure. A mixed thread remains open while any substantive concern remains.

This replaces the old unconditional "resolve the thread" step. Closure is a per-finding decision made after `reply` succeeds, not a step that runs by default once a reply is posted.

## CI status and unchanged files

Two of the old blanket triggers no longer apply as written:

- **CI failure comment.** If it carries a substantive diagnostic (a named failing check, a stack trace, a broken assertion), investigate whether a changed file in this PR actually caused it before classifying; a changed caller can break an unchanged callee. Only a pure status notification with no diagnostic content ("CI passed", "Coverage: 92%") gets skipped quietly: no reply, no thread mutation, no classification needed.
- **File not changed in this PR.** Don't default to `NOT_APPLICABLE`. An unchanged file can be the callee of a changed caller, or the affected file in a genuinely valid `OUT_OF_SCOPE` finding. Check the dependency before classifying either way.

## `--dry-run` and `--no-resolve`

- `--dry-run`: run `resolve-identity`, `resolve-comment`, `snapshot`, and `patch-context` only. Print the classification, the evidence, and the proposed `stage-commit`/`publish`/`reply`/`resolve-thread` plan. Never call `worktree prepare`, `stage-commit`, `publish`, `reply`, `resolve-thread`, `state write`, or the closing self-improve log.
- `--no-resolve`: run the full authorized fix/reply workflow (worktree, stage-commit, publish, and reply all execute normally) but never call `resolve-thread`. Use this when the reviewer wants to keep control of closure.

## Reply

- Write the reply body to a file and pass `--body-file`. Never build it inline in a shell string; a comment (or your own reply) containing backticks, `$()`, or quotes cannot be allowed to execute anything.
- `ACTIONABLE_FIX`, once `publish` has confirmed `matches_pushed_commit: true`: one sentence naming the file and what changed. The literal string `✅ Fixed` is the last thing in the body, with nothing after it. Never use this suffix on a pending, failed, local-only, or unvalidated change.
- `INFORMATIONAL`: state the actual outcome. Answer with evidence, or explain plainly why no reply is needed for a pure status message. Don't force "no change needed" onto every informational reply if that isn't actually true.
- `NOT_APPLICABLE`: name the specific evidence that disproves the premise. Leave a disputed case for the reviewer instead of asserting certainty you don't have.
- An issue (PR conversation) comment has no thread to resolve. Reply without `--thread-node-id`, then skip `resolve-thread` entirely for that comment.

## Report

After each finding, output one line naming the classification, the execution state, and the discussion state separately, for example:

```
[ACTIONABLE_FIX] #<comment_id> — fixed, pushed <sha>, thread open pending CI
[INFORMATIONAL] #<comment_id> — answered, no resolution attempted (not eligible)
[ACTIONABLE_FIX] #<comment_id> — blocked, validation failed, no reply posted
```

When `--all` finishes, print a summary table with the same three states kept separate:

```
| Comment | Author | Classification | Execution | Discussion |
|---|---|---|---|---|
| #<id> | @<login> | ACTIONABLE_FIX | Published <sha> | Replied, resolved |
| #<id> | @<login> | INFORMATIONAL  | N/A | Replied, open |
| #<id> | @<login> | ACTIONABLE_FIX | Blocked: validation failed | No reply |
```

Never claim every comment was processed if a page, a scope, or a partial GraphQL response was excluded; say so instead.

## Closing: optional learning capture

Attempt `/platform-skills:self-improve log` only when every one of these holds: the run is not `--dry-run`; `/platform-skills:self-improve` is actually available in this installation; and the finding required a non-obvious correction, not routine boilerplate. Otherwise skip it silently and note the skip in the final summary. This is an optional closing integration, never a prerequisite for finishing triage, and it must not run during `--dry-run`.

## Never do these

- Never classify `ALREADY_FIXED` or `NOT_APPLICABLE` because a search for the flagged identifier came up empty. Check `patch-context` for a rename or syntax change first.
- Never call `stage-commit` before validation reports PASS, `publish` before `stage-commit` succeeds, or `resolve-thread` before `reply` returns `CONFIRMED`/`ALREADY_REPLIED`.
- Never resolve an `INFORMATIONAL`, `NEEDS_CLARIFICATION`, `OUT_OF_SCOPE`, or disputed `NOT_APPLICABLE` finding by default. Closure is per-finding.
- Never treat a CI-failure comment carrying a real diagnostic as automatically `NOT_APPLICABLE`, and never treat an unchanged file as automatically out of scope. Either can hide a real dependency.
- Never edit the caller's own checkout directly. Always work inside the `worktree prepare` isolation.
- Never build a reply body inline in a shell string. Always write it to a file and pass `--body-file`.
- Never call `snapshot` more than once per run.
- Never run `/platform-skills:self-improve log` during `--dry-run`, or for a routine, obvious correction.

## Always do these

- Always run `resolve-identity` and `resolve-comment` before reading or acting on comment content.
- Always confirm `matches_pushed_commit: true` before writing a reply that claims the fix is live.
- Always release the `state lock` in Phase H, even when the run ends early or blocked.
- Always report classification, execution state, and discussion state separately. A comment can legitimately end a run "fixed, pushed, thread still open pending CI."
