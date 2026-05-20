# Learnings Log

Positive learnings, useful techniques, and patterns that worked well.
Captured automatically during agent sessions or logged manually.

Format: `LRN-YYYYMMDD-NNN`
Lifecycle: `pending → resolved → promoted`

---

### LRN-20260520-001
**Status**: example
**Context**: Running `helm diff upgrade` before applying a Helm release
**Content**: `helm diff upgrade` produces a clean diff of rendered manifest changes without touching the cluster. It is faster than `kubectl diff` and surfaces Helm-specific template changes (e.g. auto-generated labels) that would otherwise be invisible.
**Action**: Add `helm diff upgrade` as a pre-apply step in the helmcheck command; promote to `.github/copilot-instructions.md` as a standard practice.

---
