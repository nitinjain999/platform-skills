# PR Review Examples

Realistic before/after scenarios for each `/platform-skills:pr-review` mode. Each example shows the input that triggers a finding and the expected output the command produces.

## Structure

```
cost/
  deployment-replica-increase.yaml   # Replica bump + missing resource requests
  terraform-nat-gateway.tf           # Redundant NAT Gateways per subnet vs per AZ

drift/
  values-dev.yaml                    # Dev Helm values with ssl-redirect + feature flag
  values-prod.yaml                   # Prod Helm values missing those keys
  kustomization-prod.yaml            # Prod overlay missing HPA patch present in dev/staging

ownership/
  missing-codeowners.txt             # New top-level directory with no CODEOWNERS entry
  namespace-missing-labels.yaml      # Namespace with no team label or ResourceQuota

compliance/
  iam-wildcard.tf                    # Wildcard IAM (CC6.1) + unencrypted RDS (CC6.7)

upgrade/
  deprecated-apis.yaml               # networking.k8s.io/v1beta1, batch/v1beta1 (removed 1.22/1.25)
  terraform-loose-constraints.tf     # ">= 3.0" provider constraint, unversioned module source

rollback/
  rds-storage-increase.tf            # Irreversible RDS storage increase + prevent_destroy removal
  resource-rename.yaml               # Deployment rename with prune:true + broken Service selector
```

## Quick Start

Get the diff for a real PR and pipe it in:

```bash
gh pr diff 42 | pbcopy    # macOS
```

Then in Claude:

```
/platform-skills:pr-review cost
[paste diff]
```

Or run all modes at once:

```
/platform-skills:pr-review full 42
```

## Example by Mode

### cost

```
/platform-skills:pr-review cost

[paste examples/pr-review/cost/deployment-replica-increase.yaml diff]
```

Expected findings:
- `[COST] HIGH` — replica increase with estimated $/month delta
- `[COST] MEDIUM` — missing resource requests on containers

### drift

```
/platform-skills:pr-review drift

values-dev.yaml: [paste]
values-prod.yaml: [paste]
```

Expected findings:
- `[DRIFT] HIGH` — ssl-redirect annotation missing in prod
- `[DRIFT] MEDIUM` — featureFlags.newCheckoutFlow absent in prod
- `[DRIFT] MEDIUM` — resources.requests missing in prod

### ownership

```
/platform-skills:pr-review ownership

[paste diff adding platform/ directory]
```

Expected findings:
- `[OWNERSHIP] HIGH` — no CODEOWNERS entry for new path
- `[OWNERSHIP] MEDIUM` — new Terraform module with no README
- `[OWNERSHIP] MEDIUM` — Namespace with no team label

### compliance

```
/platform-skills:pr-review compliance

[paste examples/pr-review/compliance/iam-wildcard.tf diff]
```

Expected findings:
- `[COMPLIANCE] CC6.1 CRITICAL` — wildcard IAM action and resource
- `[COMPLIANCE] CC6.7 CRITICAL` — RDS storage_encrypted = false

### upgrade

```
/platform-skills:pr-review upgrade

[paste examples/pr-review/upgrade/deprecated-apis.yaml diff]
```

Expected findings:
- `[UPGRADE] BREAKING` — networking.k8s.io/v1beta1 removed in 1.22
- `[UPGRADE] BREAKING` — batch/v1beta1 removed in 1.25

### rollback

```
/platform-skills:pr-review rollback

[paste examples/pr-review/rollback/rds-storage-increase.tf diff]
```

Expected findings:
- `[ROLLBACK] Reversibility: NONE, Blast radius: DATA` — RDS storage increase
- `[ROLLBACK] Reversibility: MANUAL` — prevent_destroy removal
- Rollback Risk Score: 🔴 HIGH

### full

```
/platform-skills:pr-review full

[paste complete diff]
```

Produces all six sections in sequence, ending with a **Merge Readiness Summary**:

```
Cost delta:      +$280/month (2 findings)
Drift:           3 environment mismatches
Ownership gaps:  2 findings
Compliance:      2 control areas affected (2 critical)
Upgrade risk:    2 deprecated items (2 breaking)
Rollback score:  🔴 HIGH

Blockers (must fix before merge):
  - Wildcard IAM (CC6.1)
  - Unencrypted RDS (CC6.7)
  - RDS storage increase: take snapshot first
  - networking.k8s.io/v1beta1 Ingress (removed in 1.22)
```

## See Also

- [references/pr-review.md](../../references/pr-review.md) — full reference with pricing tables, SOC 2 control mapping, Kubernetes deprecation timeline, and rollback decision matrix
- [commands/pr-review.md](../../commands/pr-review.md) — slash command definition with all mode specs
- `/platform-skills:review` — production-readiness review for a single manifest or file
