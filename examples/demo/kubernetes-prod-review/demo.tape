Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── bad.yaml (what ships without platform-skills) ───'"
Enter
Sleep 500ms
Type "cat bad.yaml"
Enter
Sleep 3s

Type "echo ''"
Enter
Type "echo '─── platform-skills review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  Plaintext DATABASE_URL in env — visible in kubectl get pod -o yaml'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  image:latest — non-deterministic, no rollback path'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  No resources requests/limits — node starvation, OOMKill risk'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  No readinessProbe — traffic routed to unready pods on startup'"
Enter
Sleep 200ms
Type "echo '⚠️  IMPROVE  No securityContext — container runs as root, writable filesystem'"
Enter
Sleep 200ms
Type "echo '⚠️  IMPROVE  No NetworkPolicy — pod accepts traffic from any source'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── fixed.yaml (after platform-skills review) ───'"
Enter
Sleep 500ms
Type "cat fixed.yaml"
Enter
Sleep 4s

Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "echo '✅ fixed.yaml is valid YAML'"
Enter
Sleep 1s
