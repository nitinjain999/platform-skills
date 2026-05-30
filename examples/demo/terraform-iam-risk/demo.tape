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
Type "echo '❌ CRITICAL  Action:* — grants full AWS access to this role'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  Resource:* — no scope boundary on any service'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      No Condition on AssumeRole — usable from any region'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    Single catch-all statement — impossible to audit in CloudTrail'"
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
