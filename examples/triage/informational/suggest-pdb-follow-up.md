# Informational: "Consider adding a PDB"

## Comment

**Author:** `@dave` (human reviewer)
**PR:** Adds a new Deployment for the notifications service

> This Deployment has no PodDisruptionBudget. During a node drain,
> all replicas could be evicted simultaneously. Worth adding in a follow-up
> to protect against that.

---

## Classification: INFORMATIONAL

**Reason:** The suggestion is valid but explicitly marked as "follow-up" by the reviewer.
Adding a PDB requires knowing the correct `minAvailable` value, which requires load testing
this new service first. Out of scope for an initial rollout PR.

---

## Fix: none

---

## Reply posted on thread

> Agreed — a PDB is the right call once we have a baseline for this service.
>
> Adding it now would require picking a `minAvailable` value blind, which risks
> either breaking rolling deploys (too high) or providing no real protection (too low).
> The plan is to run load tests in staging during the first week, then add the PDB
> in a follow-up PR with measured values.
>
> Tracked in issue #112.
>
> ℹ️ Thread resolved — no code change needed.

---

## When a human would triage this manually

1. Reviewer said "in a follow-up" — this is a suggestion, not a blocker
2. No existing PDB to compare against for this new service
3. Correct response: acknowledge, explain why not now, create a tracking issue, resolve
