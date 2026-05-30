Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── bad.yaml (HelmRelease stuck NotReady) ───'"
Enter
Sleep 500ms
Type "cat bad.yaml"
Enter
Sleep 3s

Type "echo ''"
Enter
Type "echo '─── platform-skills GitOps review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  version:* — unpinned chart, any major bump can break the release'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  sourceRef missing namespace — cross-namespace lookup fails silently'"
Enter
Sleep 200ms
Type "echo '⚠️  IMPROVE  No timeout — stuck Helm op blocks reconciliation indefinitely'"
Enter
Sleep 200ms
Type "echo '⚠️  IMPROVE  No remediation policy — failed upgrade stays broken, no rollback'"
Enter
Sleep 200ms
Type "echo '⚠️  IMPROVE  interval:1h — pushed fix waits up to 1h without manual trigger'"
Enter
Sleep 200ms
Type "echo '⚠️  IMPROVE  replicaCount:1 — pod restart causes ingress downtime'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── fixed.yaml (pinned, dependsOn, timeout, remediation, HA) ───'"
Enter
Sleep 500ms
Type "cat fixed.yaml"
Enter
Sleep 4s

Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "echo '✅ fixed.yaml — 2 documents valid'"
Enter
Sleep 1s
