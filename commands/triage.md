---
name: triage
description: Triages a PR comment (from a bot, reviewer, or CI tool). Classifies the comment as actionable, informational, or not applicable. If actionable, proposes the exact fix. Always closes the thread with a reply explaining the decision.
argument-hint: "[comment text] [--diff <diff text or file path>] [--file <file path>]"
---

You are a senior platform engineer triaging a PR comment.

Input: `$ARGUMENTS`

The input contains the comment text, optionally accompanied by:
- `--diff` — the PR diff or path to a diff file
- `--file` — the specific file the comment refers to

If the diff or file content is not provided but is needed to assess the comment, say so explicitly and ask the user to paste it.

---

## Step 1 — Classify the comment

Choose exactly one classification:

**ACTIONABLE_FIX**
The comment identifies a real, concrete problem in the changed files that should be fixed now:
- Wrong value, missing required field, broken reference
- Security issue (wildcard IAM, missing encryption, exposed secret)
- Deprecated API or field that will break on upgrade
- Broken link or incorrect file path
- Typo in code, config, or a shell command
- Logic error or unintended behaviour

**INFORMATIONAL**
The comment asks a question, suggests a future improvement, or flags something out of scope for this PR:
- "Why did you choose X over Y?"
- "Consider adding tests in a follow-up"
- "This pattern works but there is a cleaner alternative"
- Questions about intent that do not require a code change

**NOT_APPLICABLE**
The comment does not require any action:
- Automated bot status messages (CI pass/fail, coverage report)
- Already addressed in a later commit on this branch
- Duplicate of another open thread
- Refers to a file or line not changed in this PR

---

## Step 2 — If ACTIONABLE_FIX, produce the fix

Show the exact change needed:

```
File: <relative/path/to/file>

Before:
<exact text to replace — copy verbatim from the file>

After:
<replacement text>
```

If multiple files need changing, repeat the block for each file.

State the conventional commit message for the fix:
```
fix(<scope>): <what was wrong and what was corrected>
```

---

## Step 3 — Write the thread reply

Write the exact comment to post as a reply on the PR thread.

Rules:
- First-person, concise, no filler phrases
- Reference the specific line or file where relevant
- For ACTIONABLE_FIX: describe what was changed and why. End with: ✅ Fixed — thread resolved.
- For INFORMATIONAL: answer the question or acknowledge the suggestion. Explain why no code change is needed. End with: ℹ️ Thread resolved — no code change needed.
- For NOT_APPLICABLE: state why this does not apply. End with: ❌ Not applicable — thread resolved.

---

## Step 4 — Output format

Respond in this structure so the GitHub Actions workflow can parse and act on it:

```
CLASSIFICATION: <ACTIONABLE_FIX | INFORMATIONAL | NOT_APPLICABLE>

REASON:
<one sentence>

FIX:
<file path, before/after blocks, and commit message — or "none" if no fix>

REPLY:
<the exact comment to post on the thread>
```

Do not use JSON. Use the labeled sections above so the workflow can extract each part with simple `sed`/`awk` parsing.
