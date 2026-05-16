# Product Examples

Status: Stable

Working examples for the `/platform-skills:product` command — DevEx audits, RFC/ADR drafts, incident updates, and post-mortems.

## How the Command Works

```
/platform-skills:product devex
/platform-skills:product rfc
/platform-skills:product adr
/platform-skills:product incident
/platform-skills:product postmortem
/platform-skills:product capacity
```

---

## Examples

### post-mortem-template.md

A blameless post-mortem following the standard structure: timeline, impact, root cause, contributing factors, action items.

**Scenario:** Database failover at 02:15 UTC caused 18 minutes of checkout downtime. Root cause: missing health check on standby replica.

```markdown
# Post-Mortem: Checkout Downtime — 2026-05-12

**Severity:** P1  
**Duration:** 18 minutes (02:15–02:33 UTC)  
**Services affected:** checkout-api, payments-service  
**On-call:** @alice

## Impact

- 100% of checkout requests failed for 18 minutes
- Estimated 2,400 failed transactions
- No data loss — all in-flight orders rolled back via idempotency keys

## Timeline

| Time (UTC) | Event |
|---|---|
| 02:15 | Primary RDS instance fails; automatic failover initiates |
| 02:17 | Failover completes — standby promoted to primary |
| 02:17 | checkout-api health checks fail — standby not accepting connections |
| 02:18 | PagerDuty alert fires |
| 02:22 | On-call acknowledges, starts investigation |
| 02:28 | Root cause identified: pg_hba.conf not replicated to standby |
| 02:33 | pg_hba.conf copied, connections restored, traffic recovers |

## Root Cause

The standby replica was promoted but its `pg_hba.conf` lacked the `checkout-api` service account entry. PostgreSQL rejected all connections from the application.

## Contributing Factors

- Standby configuration was not validated as part of the RDS module
- No automated failover drill had been run in 8 months
- Health check timeout was 30s — alert fired 3 minutes after failure

## Action Items

| Action | Owner | Due |
|---|---|---|
| Add pg_hba.conf validation to Terraform RDS module | @alice | 2026-05-19 |
| Run quarterly failover drill and document in runbook | @bob | 2026-06-01 |
| Reduce health check timeout from 30s to 10s | @alice | 2026-05-14 |
| Add runbook link to PagerDuty alert | @carol | 2026-05-14 |

## What Went Well

- Idempotency keys prevented duplicate charges
- On-call reached root cause within 6 minutes of acknowledgement
- Rollback was safe — no manual data intervention needed
```

---

### rfc-template.md

An RFC for a significant platform change requiring cross-team review.

**Scenario:** Migrating from Argo CD to Flux CD across 15 teams.

```markdown
# RFC: Migrate from Argo CD to Flux CD

**Status:** Draft  
**Author:** @platform-team  
**Reviewers:** @alice, @bob, @dave  
**Decision by:** 2026-06-15

## Problem

Argo CD and Flux CD are both active in production, managing overlapping namespaces. This creates dual-reconciler conflicts, unclear ownership, and duplicated platform effort.

## Proposed Solution

Standardise on Flux CD for all in-cluster GitOps. Migrate 15 teams over 8 weeks using a parallel-run approach.

## Migration Plan

| Week | Scope |
|---|---|
| 1–2 | Bootstrap Flux on all clusters alongside Argo CD |
| 3–4 | Migrate platform add-ons (cert-manager, ingress, Linkerd) |
| 5–6 | Migrate application teams in waves (4 teams/wave) |
| 7 | Decommission Argo CD ApplicationSets |
| 8 | Remove Argo CD Helm release and CRDs |

## Risks

| Risk | Mitigation |
|---|---|
| Flux and Argo CD reconcile same resource simultaneously | Set Argo CD app to `ignoreDifferences` for migrated resources during cutover |
| Team GitOps repos need restructuring | Provide migration script and 1:1 pairing sessions |
| Flux outage during migration | Keep Argo CD as fallback until week 7 |

## Alternatives Considered

- Keep Argo CD only: Flux is already managing platform add-ons; migration overhead is lower than maintaining both.
- Keep both permanently: dual-reconciler conflicts are unsustainable at scale.
```

---

### adr-template.md

An Architecture Decision Record for a narrower, already-decided choice.

```markdown
# ADR-012: Use External Secrets Operator for Secret Injection

**Date:** 2026-04-10  
**Status:** Accepted  
**Deciders:** Platform team

## Context

Applications need access to secrets stored in AWS Secrets Manager. Options evaluated:
1. Mount secrets as environment variables via Kubernetes Secrets committed to Git
2. Use AWS Secrets Manager CSI driver
3. Use External Secrets Operator (ESO)

## Decision

Use External Secrets Operator (ESO) with `ClusterSecretStore` backed by AWS Secrets Manager.

## Consequences

- **Good:** ESO rotates secrets automatically on a configurable schedule; no manual Kubernetes Secret updates.
- **Good:** Secret values never appear in Git or Terraform state.
- **Bad:** ESO adds an operator dependency; must be managed as a platform component.
- **Neutral:** Application teams write `ExternalSecret` CRDs instead of referencing existing Secrets.
```

---

## See Also

- [commands/product.md](../../commands/product.md) — full command definition with all modes
- [references/platform-operating-model.md](../../references/platform-operating-model.md) — platform product thinking and operating model
