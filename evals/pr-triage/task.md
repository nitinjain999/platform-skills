# Task: Triage a PR review comment

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

1. Classify this comment as ACTIONABLE_FIX, INFORMATIONAL, or NOT_APPLICABLE.
2. If ACTIONABLE_FIX: show the corrected YAML with appropriate resource requests and limits.
3. Explain the blast radius of the change and provide a rollback plan.
4. Write the reply you would post on the review thread.
