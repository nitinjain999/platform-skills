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
Type "echo '❌ CRITICAL  actions/checkout@main — tag can be moved to malicious commit'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  permissions:write-all — any step gets full repo write access'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      AWS long-lived keys in secrets — leaked key = permanent access'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      actions/setup-node@main — same supply chain risk'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      configure-aws-credentials@main — same supply chain risk'"
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
Type "python3 -c \"import yaml; yaml.safe_load(open('fixed.yml')); print('✅ YAML valid')\""
Enter
Sleep 1s
