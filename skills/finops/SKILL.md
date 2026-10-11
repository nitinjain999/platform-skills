---
name: finops
description: Cost visibility and tag governance for platform changes. Estimates the monthly cost of a Terraform pull request with Infracost, sets up in-cluster cost allocation by namespace and label with OpenCost, and enforces required cost tags in four layers (Terraform default_tags and variable validation, a Conftest gate on the plan, AWS Config REQUIRED_TAGS, and a Kyverno namespace-label policy). Use when asked "what will this cost", "add cost estimates to PRs", "who owns this spend", "enforce cost-center tags", or "set up OpenCost". Cost as one dimension of a full PR review → /platform-skills:pr-review.
argument-hint: "[estimate|allocate|tags|audit] [path, PR or namespace]"
title: "FinOps Command"
sidebar_label: "finops"
custom_edit_url: null
---

Make cost visible before a change merges, attributable after it runs, and impossible to leave untagged.

Read `references/finops.md` before responding. It holds the four-layer tag pattern and what each layer misses, the Infracost workflow and CLI, OpenCost configuration, and rollback. The working files are in `examples/finops`.

The required tag keys for this organisation are `${user_config.required_tag_keys}`. If that reads as a literal placeholder or is empty, it is not configured: use `owner, cost-center, environment` and say so.

## Mode dispatch

| Mode | What it does |
|---|---|
| `estimate` | Monthly cost difference of a Terraform change with Infracost; the PR workflow from `examples/finops/workflows/infracost.yml` |
| `allocate` | OpenCost via Flux, pointed at the user's Prometheus, with a per-cluster ID |
| `tags` | The four-layer tag enforcement for the user's keys: provider `default_tags` and validation, the Conftest policy and its tests, the AWS Config rule, the Kyverno policy (Audit first) |
| `audit` | Find untagged resources and unowned namespaces now: AWS Config compliance for `REQUIRED_TAGS`, namespaces missing cost labels, OpenCost's idle and unallocated cost |

## Rules

- Keep the tag key list identical in every layer, and state it once at the top of the output.
- Never suggest bypassing the CI gate for a single change; fix the tags or change the rule in Git.
- Treat Infracost output as a direction: name the usage assumptions it could not know.

## Output format

Every mode ends with:

- **Changes**, as exact files and fields
- **Blast radius**, in one line
- **Validation**, as commands (`opa test`, `conftest test`, `kubeconform`, `infracost diff`)
- **Rollback**
