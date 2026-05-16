# Informational: "Why only 2 replicas?"

## Comment

**Author:** `@carol` (human reviewer)
**PR:** Bumps orders-service image tag to `1.4.2`

> Why is `replicas: 2`? Is that enough for production traffic?
> Just want to understand the reasoning before approving.

---

## Classification: INFORMATIONAL

**Reason:** The reviewer is asking for context about an intentional design decision.
The replica count is correct for the current load profile. No code change is needed.

---

## Fix: none

---

## Reply posted on thread

> Two replicas gives N+1 redundancy for the expected 200 RPS baseline load
> (each pod handles ~200 RPS at 60% CPU with the current resource limits).
>
> The HPA is configured to scale up to 10 replicas when CPU exceeds 70%, so
> burst traffic is covered automatically. The PodDisruptionBudget ensures at
> least 1 replica is always available during rolling deploys and node drains.
>
> If you want to verify the HPA config:
> ```bash
> kubectl get hpa orders -n checkout
> ```
>
> ℹ️ Thread resolved — no code change needed.

---

## When a human would triage this manually

1. Read the comment — it ends with "just want to understand", not "this needs to be changed"
2. Look at the Deployment: HPA exists, PDB exists, resource requests are set
3. Classify as INFORMATIONAL
4. Answer the question with evidence (HPA max, current RPS, PDB)
5. Resolve the thread
