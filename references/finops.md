---
title: FinOps
custom_edit_url: null
---

# FinOps Reference

Covers all `/platform-skills:finops` mode logic: cost estimates on pull requests with Infracost, in-cluster cost allocation with OpenCost, and a tag-enforcement pattern that holds across Terraform, CI, the AWS account and Kubernetes.

**Verified against:** Infracost CLI 0.10.x and `infracost/actions/diff` v4.2.0, OpenCost chart 2.5.32 (OpenCost 1.121.3), AWS Config managed rule `REQUIRED_TAGS`, Kyverno `policies.kyverno.io/v1`. Working example: `examples/finops`.

## Ownership boundary

| Question | Authoritative skill |
|---|---|
| What will this change cost, where is spend going, why are resources untagged | **`/platform-skills:finops`** |
| Cost as one dimension of a PR review | `/platform-skills:pr-review` (cost mode points here for the tooling) |
| Writing or testing the Rego policy itself | `/platform-skills:opa` |
| Writing or testing the Kyverno policy itself | `/platform-skills:kyverno` |
| Right-sizing nodes and Spot strategy | `/platform-skills:karpenter` |
| Capacity planning | `/platform-skills:product` |

## Tag enforcement in four layers

One layer is never enough: each misses a path the next one catches.

| Layer | Mechanism | Misses |
|---|---|---|
| 1. Terraform provider | `default_tags` from a validated `required_tags` variable | Resources outside Terraform; resources whose own `tags` override a default with an empty value |
| 2. CI | Conftest on `terraform show -json` output, checking `tags_all` (or `tags`) of every created or updated `aws_*` resource | Anything not deployed through that pipeline |
| 3. AWS account | AWS Config `REQUIRED_TAGS` (up to six keys, `tag1Key`…`tag6Key`) | Nothing in the account, but it detects after the fact; pair it with remediation or a report |
| 4. Kubernetes | Kyverno `ValidatingPolicy` on namespaces (and workloads if you allocate by workload) | Cloud resources |

Keep the key list identical in all four. Start the Kyverno policy in `Audit`; promote to `Deny` once PolicyReports show zero violations (`/platform-skills:kyverno`).

AWS Organizations tag policies and service control policies can enforce tags at creation time across accounts; they are the next step when Config detection is not enough, and they belong to the account-level governance owner.

## Cost on pull requests (Infracost)

`infracost/actions/diff` checks out base and head, estimates both, and posts one PR comment it keeps updated. It needs an `INFRACOST_API_KEY` secret. Pin the action to its commit SHA, give the job only `contents: read` and `pull-requests: write`, and check out with `persist-credentials: false`; `examples/finops/workflows/infracost.yml` does all three.

Locally, or with the CLI in your own pipeline:

```bash
infracost breakdown --path=. --format=json --out-file=/tmp/infracost-base.json   # on the base branch
infracost diff --path=. --format=json --compare-to=/tmp/infracost-base.json --out-file=/tmp/infracost.json
infracost comment github --path=/tmp/infracost.json --repo=$GITHUB_REPOSITORY \
  --github-token=$GITHUB_TOKEN --pull-request=<number> --behavior=update
```

Read the estimate as a direction, not an invoice: usage-based costs (data transfer, requests, Lambda invocations) depend on usage you have not described.

## In-cluster allocation (OpenCost)

OpenCost reads usage from Prometheus and prices it, then allocates cost by namespace, label, controller and pod. It needs a Prometheus that scrapes the cluster (`opencost.prometheus.internal` for an in-cluster service, `external.url` otherwise). Set `opencost.exporter.defaultClusterId` per cluster so multi-cluster data stays separable. Allocation by label only works if the labels exist, which is what layer 4 enforces.

## Rollback

| Change | Rollback |
|---|---|
| A tag rule blocks a legitimate change | Fix the tags in the change; if the rule itself is wrong, revert it in Git. Never bypass the gate for one PR |
| Kyverno promoted to `Deny` too early | Set `validationActions` back to `[Audit]` |
| OpenCost misbehaves | Revert or suspend its HelmRelease; it is read-only and affects no workload |
| Infracost comment noise | Narrow the workflow `paths`; the action never blocks a merge on its own |
