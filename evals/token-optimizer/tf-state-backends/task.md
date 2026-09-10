# Task: Find every Terraform backend and state key

Scan all Terraform configurations under `terraform/` and report every backend configuration.

For each backend, report:
- The backend type (s3, azurerm, gcs, local, etc.)
- The state key or path
- The bucket or storage account name
- Any locking configuration

State what was omitted or truncated. Report complete, partial, or blocked.
