Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── bad.tf (Action: * — silent AdministratorAccess) ───'"
Enter
Sleep 500ms
Type "cat bad.tf"
Enter
Sleep 3s

Type "echo ''"
Enter
Type "echo '─── platform-skills IAM review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  Action:* — every AWS API call including iam:* and ec2:Terminate'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  Resource:* — applies to every resource in the account'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      Inline policy — cannot be reused, audited centrally, or versioned'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    var.app_name has no type or validation — empty string = broken role name'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── fixed.tf (least privilege — scoped actions and resources) ───'"
Enter
Sleep 500ms
Type "cat fixed.tf"
Enter
Sleep 4s

Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "echo '✅ HCL format correct — terraform fmt -check passed'"
Enter
Sleep 1s
