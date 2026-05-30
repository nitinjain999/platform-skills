Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── PR #42 has 3 open review threads ───'"
Enter
Sleep 500ms
Type "echo 'Thread 1: Missing securityContext — container runs as root'"
Enter
Sleep 200ms
Type "echo 'Thread 2: Consider adding a PodDisruptionBudget for HA'"
Enter
Sleep 200ms
Type "echo 'Thread 3: Why not use Knative here?'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── running: /platform-skills:triage --all 42 ───'"
Enter
Sleep 1s

Type "echo ''"
Enter
Type "echo '── Thread 1 ──────────────────────────────────────────'"
Enter
Sleep 300ms
Type "echo 'Classification: ACTIONABLE_FIX'"
Enter
Sleep 300ms
Type "echo 'Reading deployment.yaml...'"
Enter
Sleep 500ms
Type "echo 'Applying fix: adding securityContext at pod and container level'"
Enter
Sleep 500ms
Type "echo 'Committed: fix: add securityContext to payment-api deployment [skip ci]'"
Enter
Sleep 300ms
Type "echo 'Reply posted ✅   Thread resolved ✅'"
Enter
Sleep 1s

Type "echo ''"
Enter
Type "echo '── Thread 2 ──────────────────────────────────────────'"
Enter
Sleep 300ms
Type "echo 'Classification: INFORMATIONAL'"
Enter
Sleep 300ms
Type "echo 'No file change needed — replying with context'"
Enter
Sleep 500ms
Type "echo 'Reply: PDB is tracked in issue #87 — out of scope for this PR'"
Enter
Sleep 300ms
Type "echo 'Reply posted ✅   Thread resolved ✅'"
Enter
Sleep 1s

Type "echo ''"
Enter
Type "echo '── Thread 3 ──────────────────────────────────────────'"
Enter
Sleep 300ms
Type "echo 'Classification: NOT_APPLICABLE'"
Enter
Sleep 300ms
Type "echo 'No file change — replying with rationale'"
Enter
Sleep 500ms
Type "echo 'Reply: Knative is not in our platform stack — closing as not applicable'"
Enter
Sleep 300ms
Type "echo 'Reply posted ✅   Thread resolved ✅'"
Enter
Sleep 1s

Type "echo ''"
Enter
Type "echo '─── triage complete ───'"
Enter
Sleep 500ms
Type "echo '3 threads processed: 1 fix applied, 2 informational, 0 skipped'"
Enter
Sleep 2s
