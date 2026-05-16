# Not Applicable: already fixed in a later commit

## Comment

**Author:** `@frank` (human reviewer)
**PR:** Refactors the orders service Helm chart
**Comment posted on:** commit `a1b2c3d` (first commit on the branch)

> The `latest` image tag on line 9 needs to be pinned to a specific
> digest or version tag before this can merge.

---

## Classification: NOT_APPLICABLE

**Reason:** Commit `a3f91b2` (three commits later on the same branch) already pins the
image tag to `orders:1.4.2@sha256:abc123...`. The issue is resolved in the current
HEAD of the branch — the comment is stale.

---

## How triage detects this

```bash
# Check current HEAD of the file the comment refers to
git show HEAD:path/to/deployment.yaml | grep image:
# image: orders:1.4.2@sha256:abc123def456...   ← already pinned

# The comment was made on an older commit — the fix is already present
```

---

## Fix: none

---

## Reply posted on thread

> This was already addressed in commit `a3f91b2` — the image is now pinned
> to `orders:1.4.2@sha256:abc123def456...` which is an immutable reference.
>
> ❌ Not applicable — thread resolved.
