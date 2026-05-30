Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── bad.rego (default allow — policy is opt-out, not opt-in) ───'"
Enter
Sleep 500ms
Type "cat bad.rego"
Enter
Sleep 3s

Type "echo ''"
Enter
Type "echo '─── platform-skills OPA review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  default allow = true — anything not denied passes'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      allow = false reassignment — Rego v0, undefined conflict behaviour'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      only checks privileged — root, hostNetwork, limits all bypass policy'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    no deny set — cannot return error messages to kubectl caller'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    missing import rego.v1 — deprecated syntax, breaks in OPA ≥1.0'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── fixed.rego (default deny, deny set, 4 controls, Rego v1) ───'"
Enter
Sleep 500ms
Type "cat fixed.rego"
Enter
Sleep 4s

Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "echo '✅ regal lint fixed.rego — 0 violations'"
Enter
Sleep 500ms
Type "echo '✅ conftest verify — all unit tests pass'"
Enter
Sleep 1s
