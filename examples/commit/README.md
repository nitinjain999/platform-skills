# Commit Examples

Status: Stable

Working examples for the `/platform-skills:commit` command — generating, validating, and staging conventional commit messages.

## How the Command Works

```
/platform-skills:commit analyze
/platform-skills:commit generate
/platform-skills:commit stage
/platform-skills:commit validate "fix(auth): handle token expiry on refresh"
```

Claude:
1. Reads staged or unstaged git diff
2. Classifies the change type (`feat`, `fix`, `refactor`, `chore`, `ci`, `docs`, `test`, `perf`)
3. Drafts a subject line: `<type>(<scope>): <imperative WHY, ≤72 chars>`
4. Optionally stages related files and commits
5. Validates an existing message against Conventional Commits 1.0.0 spec

Never adds `Co-authored-by: Claude` or any AI attribution.

---

## Examples

### good-commit-message.txt

A correctly formatted conventional commit message with body and footer.

**Before (vague message):**
```
Fix: updated auth service
```

**After (`/platform-skills:commit validate`):**
```
❌ Subject must use lowercase type — "Fix" is not valid
❌ Missing scope — use fix(auth): or fix(service):
❌ Description starts with past tense "updated" — use imperative: "handle"
❌ Missing blank line between subject and body

Suggested: fix(auth): handle token expiry on silent refresh
```

**Valid form:**
```
fix(auth): handle token expiry on silent refresh

When the access token expires during a background refresh, the service
was returning 401 instead of retrying with the refresh token. This caused
session loss on long-lived tabs.

Resolves: #142
```

---

### diff-to-commit.diff

A representative git diff showing multiple related changes to a single concern.

```diff
diff --git a/src/auth/refresh.ts b/src/auth/refresh.ts
index a1b2c3d..e4f5a6b 100644
--- a/src/auth/refresh.ts
+++ b/src/auth/refresh.ts
@@ -12,6 +12,10 @@ export async function refreshToken(token: string): Promise<string> {
   const response = await fetch('/api/auth/refresh', {
     method: 'POST',
     body: JSON.stringify({ token }),
   });
+  if (response.status === 401) {
+    clearSession();
+    throw new TokenExpiredError('Refresh token expired — session cleared');
+  }
   return response.json();
 }
```

**Generated commit message:**
```
fix(auth): clear session and raise on expired refresh token

Previously a 401 from /api/auth/refresh was silently swallowed, leaving
the user with an invalid session. Now clears the session and raises
TokenExpiredError so callers can redirect to login.
```

---

## See Also

- [commands/commit.md](../../commands/commit.md) — full command definition with all modes
- [references/conventional-commits.md](../../references/conventional-commits.md) — Conventional Commits 1.0.0 spec and tooling
- [examples/conventional-commits/](../conventional-commits/) — commitlint and commitizen configuration examples
