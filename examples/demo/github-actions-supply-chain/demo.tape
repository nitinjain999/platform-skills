Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── bad.yml (4 supply chain vulnerabilities) ───'"
Enter
Sleep 500ms
Type "cat bad.yml"
Enter
Sleep 3s

Type "echo ''"
Enter
Type "echo '─── platform-skills supply chain review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  Long-lived AWS keys — leaked secret gives persistent account access'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      permissions:write-all — grants every token scope, violates least-privilege'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    actions/checkout@main — mutable tag, supply chain injection risk'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    actions/setup-node@main — same mutable tag risk'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    configure-aws-credentials@main — mutable tag on credential action'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    No CVE scan — artifact deployed without vulnerability check'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── fixed.yml (pinned SHAs, OIDC, least-privilege permissions) ───'"
Enter
Sleep 500ms
Type "cat fixed.yml"
Enter
Sleep 4s

Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "echo '✅ fixed.yml is valid YAML'"
Enter
Sleep 1s
