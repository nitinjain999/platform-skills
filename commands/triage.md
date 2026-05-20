---
name: triage
description: Triages a PR comment — from a bot (Copilot, CI) or a human reviewer. Fetches the comment and diff via gh CLI, classifies it, applies the fix directly to the file if valid, posts a reply on the thread, and resolves it. Run from inside the repo.
argument-hint: "<PR number> <comment ID> | --all <PR number>"
---

You are a senior platform engineer triaging PR comments.

Input: `$ARGUMENTS`

Two modes:
- `<PR number> <comment ID>` — triage one specific comment
- `--all <PR number>` — triage every unresolved comment on the PR in order

Run all `gh` commands directly. You have full access to the shell.

---

## Step 1 — Fetch the comment and context

For a single comment:
```bash
# Get the comment text
gh api repos/{owner}/{repo}/pulls/comments/<comment_id>
# or for a PR issue comment:
gh api repos/{owner}/{repo}/issues/comments/<comment_id>

# Get the PR diff
gh pr diff <pr_number>

# Get the file the comment refers to (if it's a review comment with a path)
# already available from the comment API response (.path field)
```

For `--all`:
```bash
# List all unresolved review threads
gh api graphql -f query='
  query($owner:String!, $repo:String!, $pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes {
            id isResolved
            comments(first:1) {
              nodes { databaseId body path line author { login } }
            }
          }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F pr=<pr_number>
```

---

## Step 2 — Classify the comment

Choose exactly one:

**ACTIONABLE_FIX** — a real problem in the changed files that must be fixed:
- Wrong value, missing required field, broken reference or link
- Security issue (wildcard IAM, missing encryption, exposed secret)
- Deprecated API or field
- Typo in code, config, or a command
- Logic error or unintended behaviour

**INFORMATIONAL** — question, out-of-scope suggestion, or future improvement:
- "Why did you choose X?"
- "Consider doing Y in a follow-up"
- Valid point but not blocking this PR

**NOT_APPLICABLE** — no action needed:
- Bot status messages (CI pass/fail, coverage)
- Already addressed in a later commit on this branch
- Duplicate of another thread
- Refers to a file not changed in this PR

---

## Step 3 — If ACTIONABLE_FIX, apply the fix

Read the file referenced in the comment:
```bash
cat <file_path>
```

Make the minimal correct change using the Edit tool. Do not touch unrelated lines.

Then commit:
```bash
git add <file_path>
git commit -m "fix(<scope>): <what was wrong and what was corrected>"
git push
```

---

## Step 4 — Post a reply on the thread

For a review comment:
```bash
gh api --method POST \
  repos/{owner}/{repo}/pulls/comments/<comment_id>/replies \
  --field body="<reply>"
```

For a PR issue comment:
```bash
gh pr comment <pr_number> --body "<reply>"
```

Reply rules:
- First-person, concise, no filler
- Reference the specific line or file
- **ACTIONABLE_FIX**: describe what was changed and why. End with: `✅ Fixed — thread resolved.`
- **INFORMATIONAL**: answer or acknowledge, explain why no code change. End with: `ℹ️ Thread resolved — no code change needed.`
- **NOT_APPLICABLE**: state why this does not apply. End with: `❌ Not applicable — thread resolved.`

---

## Step 5 — Resolve the thread

```bash
# Get the thread node ID (PRRT_ prefix)
gh api graphql -f query='
  query($owner:String!, $repo:String!, $pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes {
            id isResolved
            comments(first:1){ nodes{ databaseId } }
          }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F pr=<pr_number> \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved==false)
        | select(.comments.nodes[0].databaseId==<comment_id>)
        | .id'

# Resolve it
gh api graphql -f query='
  mutation($t:ID!) {
    resolveReviewThread(input:{threadId:$t}) {
      thread { isResolved }
    }
  }' -f t=<thread_node_id>
```

If the comment is an issue comment (not a review comment), there is no thread to resolve — skip this step.

---

## Step 6 — Confirm

After each comment, output one line:

```
[<classification>] #<comment_id> — <one sentence summary of action taken>
```

When `--all` mode finishes, print a summary table:

```
| Comment | Author | Classification | Action |
|---|---|---|---|
| #<id> | @<login> | ACTIONABLE_FIX | Fixed: <file>, committed <sha> |
| #<id> | @<login> | INFORMATIONAL  | Replied, thread resolved |
| #<id> | @<login> | NOT_APPLICABLE | Replied, thread resolved |
```

---

## Closing — Log learnings

After completing triage (single comment or `--all`), log any errors or learnings that surfaced:

- Each ACTIONABLE_FIX that required a non-obvious correction → log as `ERR` in `.learnings/ERRORS.md`
- Any pattern or shortcut that worked well → log as `LRN` in `.learnings/LEARNINGS.md`

Use `/platform-skills:self-improve log` for each entry worth keeping. Do not defer — log while the context is fresh.
