# Post-Mortem: [Service] [Incident Type] — [Date]

Status: Stable

**Severity:** P1 / P2 / P3
**Duration:** N minutes (HH:MM–HH:MM UTC)
**Services affected:** service-a, service-b
**On-call:** @engineer

---

## Impact

- Quantify user-facing impact (% requests failed, affected users, failed transactions)
- Note any data integrity impact
- Note any financial impact estimate

---

## Timeline

| Time (UTC) | Event |
|---|---|
| HH:MM | [First symptom observed] |
| HH:MM | [Alert fired] |
| HH:MM | [On-call acknowledged] |
| HH:MM | [Root cause identified] |
| HH:MM | [Mitigation applied] |
| HH:MM | [Full recovery confirmed] |

---

## Root Cause

One sentence describing the technical root cause. Follow with supporting evidence (log lines, metrics, traces).

---

## Contributing Factors

- Factor 1 (e.g., missing health check on standby)
- Factor 2 (e.g., no quarterly failover drill)
- Factor 3 (e.g., alert timeout too long)

---

## Action Items

| Action | Owner | Due |
|---|---|---|
| [Specific, measurable action] | @owner | YYYY-MM-DD |
| [Specific, measurable action] | @owner | YYYY-MM-DD |

---

## What Went Well

- [Thing that worked as expected]
- [Effective process or tooling]

---

## Detection

How was this incident detected? (alert, user report, on-call observation)
How long after the start of impact was it detected? What would reduce this?

---

## See Also

- [commands/product.md](../../commands/product.md) — full post-mortem and RFC command definition
- [references/platform-operating-model.md](../../references/platform-operating-model.md) — incident communication patterns
