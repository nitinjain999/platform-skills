# Feature Requests

Recurring needs that were unmet by the current skill or tool set.
Used to prioritise new platform-skills domains, commands, or examples.

Format: `FEAT-YYYYMMDD-NNN`
Lifecycle: `pending → resolved → promoted`

---

### FEAT-20260520-001
**Status**: example
**Context**: Needed to generate a KEDA ScaledObject but no domain existed yet
**Content**: Three sessions in a row required manually constructing KEDA ScaledObject and TriggerAuthentication YAML from scratch. No reference or example existed in platform-skills. Time cost per session: ~15 minutes.
**Action**: Resolved — KEDA domain added in v1.14.0 (`references/keda.md`, `commands/keda.md`, `examples/keda/`).

---
