# FinOps Example

Status: Beta

Cost visibility before and after a change, and one tag-enforcement pattern applied at every layer where an untagged resource could slip through.

| Layer | File | Catches |
|---|---|---|
| 1. Terraform | `terraform/main.tf` | `default_tags` puts the required tags on everything the provider creates; a variable validation rejects a plan without them |
| 2. CI gate | `policy/required_tags.rego` (+ tests) | Any created or updated `aws_*` resource whose plan lacks a required tag, including resources with per-resource tag overrides |
| 3. AWS account | `aws_config_config_rule.required_tags` in `terraform/main.tf` | Resources created outside Terraform, or with tags removed later (AWS Config managed rule `REQUIRED_TAGS`) |
| 4. Kubernetes | `kubernetes/require-cost-labels.yaml` | Namespaces without `owner`, `cost-center`, `environment` labels (Kyverno `ValidatingPolicy`, Audit first) |

Plus two cost views:

| What | File | When |
|---|---|---|
| Infracost | `workflows/infracost.yml` | Every pull request that changes Terraform: a comment with the monthly cost difference |
| OpenCost | `opencost/opencost.yaml` | Continuously: in-cluster cost by namespace and label, from Prometheus |

Run the policy against a plan:

```bash
terraform plan -out tfplan && terraform show -json tfplan > plan.json
conftest test --policy examples/finops/policy --namespace terraform.tags plan.json
opa test examples/finops/policy   # the policy's own tests
```

Change the required keys in one place per layer: the variable validation and Config rule in `main.tf`, `default_required` in the Rego (or `conftest --data`), and the Kyverno expression. Keep them identical; a key enforced in CI but not in AWS Config lets console-created resources through.

The full guide is `/platform-skills:finops` and `references/finops.md`.
