# Task: Locate IAM role assumptions across Terraform modules

Find every IAM role assumption in the Terraform configurations under `terraform/`.

For each role, report:
- The role name or ARN
- Which resource or data source declares the assume role policy
- The principals that can assume it
- Any conditions on the assumption

Report complete findings, partial findings if blocked, or blocked if you cannot proceed.
