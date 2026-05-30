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
Type "echo '❌ CRITICAL  version:\"*\" — unpinned chart, silent major upgrades'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      No dependsOn — deploys before cert-manager CRDs exist'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    interval:1h — changes wait up to 1 hour to reconcile'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    No timeout — stuck install blocks all other reconciliations'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    No remediation — failed upgrade never rolls back'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    replicaCount:1 — SPOF during node drain'"
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
Type "python3 -c \"import yaml; docs=list(yaml.safe_load_all(open('fixed.yaml'))); print(f'✅ {len(docs)} documents valid')\""
Enter
Sleep 1s
