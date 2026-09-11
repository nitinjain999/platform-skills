# Task: Map Terraform provider version constraints across directories

Find every Terraform provider version constraint in `terraform/`.

For each provider, report:
- The provider name (aws, azurerm, kubernetes, helm, etc.)
- The version constraint (e.g., >= 5.0.0, ~> 4.0)
- The file and directory where it's declared
- Any version conflicts across modules

Report complete, partial, or blocked.
