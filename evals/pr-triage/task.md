# Task: Triage a PR review comment

This task has two independent scenarios. Treat each on its own; do not let one scenario's evidence or classification bleed into the other.

## Scenario 1: Missing resource limits on a Kubernetes Deployment

A reviewer left the following comment on a pull request that modifies a Kubernetes Deployment manifest:

---

**File:** `apps/api/deployment.yaml`
**Comment:** "The container has no resource limits set. This will allow it to consume unbounded memory and get OOMKilled during a memory spike, taking down other pods on the same node."

**Diff context:**
```yaml
spec:
  containers:
    - name: api
      image: my-org/api:v1.2.3
      ports:
        - containerPort: 8080
```

---

1. Classify this comment as one of `ACTIONABLE_FIX`, `ALREADY_FIXED`, `INFORMATIONAL`, `NOT_APPLICABLE`, `NEEDS_CLARIFICATION`, `OUT_OF_SCOPE`, or `DUPLICATE`.
2. If ACTIONABLE_FIX: show the corrected YAML with appropriate resource requests and limits.
3. Explain the blast radius of the change and provide a rollback plan.
4. Write the reply you would post on the review thread.

## Scenario 2: Comment names a function that was renamed before the pinned PR head

A reviewer left the following comment on a pull request that touches billing logic:

---

**File:** `src/billing/invoice.py`
**Comment:** "`validate_discount_code()` never checks that `discount_percent` is between 0 and 100 — a negative value would increase the invoice total instead of discounting it. This needs a bounds check before it's multiplied against `invoice_total`."

**Current PR head (`src/billing/invoice.py`):**
```python
DISCOUNT_CODES = {
    "SAVE10": Discount(percent=10),
    "SAVE25": Discount(percent=25),
}

def apply_discount_code(code: str, invoice_total: float) -> float:
    discount = DISCOUNT_CODES.get(code)
    if discount is None:
        raise ValueError(f"Unknown discount code: {code}")
    return invoice_total * (1 - discount.percent / 100)
```

A search of the current head for the literal string `validate_discount_code` returns no matches. A later commit on this PR renamed the function to `apply_discount_code` during an unrelated refactor; no bounds check on `discount.percent` was added under either name.

---

1. Classify this comment as one of `ACTIONABLE_FIX`, `ALREADY_FIXED`, `INFORMATIONAL`, `NOT_APPLICABLE`, `NEEDS_CLARIFICATION`, `OUT_OF_SCOPE`, or `DUPLICATE`.
2. State the classification and the execution/discussion status as separate fields — do not conflate "the finding is real" with "a fix has been applied and published."
3. Explain specifically why the absence of the literal name `validate_discount_code` at HEAD does not by itself resolve the classification, and name the renamed target you investigated instead.
4. If ACTIONABLE_FIX: show the corrected code with a bounds check on `discount.percent`.
5. Write the reply you would post on the review thread.
