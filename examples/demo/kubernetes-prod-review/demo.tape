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
Type "echo '❌ CRITICAL  image:latest is unpinned — silent rollouts, non-reproducible'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  No securityContext — container runs as root, writable filesystem'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      No resources limits — OOMKill risk, noisy neighbour in production'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      No readinessProbe — traffic hits the pod before app is ready'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      DATABASE_URL hardcoded — credentials visible in kubectl describe pod'"
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
