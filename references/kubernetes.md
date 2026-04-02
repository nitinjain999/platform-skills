# Kubernetes Reference

## Contents

- Scope
- Platform baseline
- Workload patterns
- Security and policy
- Operational rules

## Scope

Use plain Kubernetes guidance for:

- Cluster baseline standards that apply across distributions
- Namespace, RBAC, network policy, and workload conventions
- Deployment, service, ingress, config, and secret operating practices
- Platform add-on dependencies that are not specific to one GitOps tool

Use Kubernetes as the common application runtime contract. Layer distribution-specific details in OpenShift guidance and reconciliation-specific details in Flux or Argo CD guidance.

## Platform baseline

Define a minimum platform baseline for every cluster:

- Namespaces with clear ownership boundaries
- Resource requests and limits on workloads
- Liveness, readiness, and startup probes
- Pod disruption budgets for critical services
- Network policies on app namespaces
- Standard labels and annotations for ownership, environment, and compliance

Prefer admission, policy, or template enforcement over relying on human review.

## Workload patterns

Prefer these defaults:

- `Deployment` for stateless applications
- `StatefulSet` only when identity or stable storage matters
- `Ingress` or `Gateway` patterns for north-south traffic
- `ConfigMap` for non-sensitive configuration and external secret stores for secrets
- Horizontal Pod Autoscaler only when requests and metrics are defined clearly

Keep manifests small, composable, and environment-agnostic where possible.

## Security and policy

- Run workloads as non-root unless there is a justified exception.
- Drop unnecessary Linux capabilities.
- Prefer read-only root filesystems where practical.
- Use service accounts intentionally; do not let everything run as `default`.
- Enforce image provenance, namespace controls, and policy checks before deployment.

## Operational rules

- Treat Git as the source of truth for declared state.
- Avoid imperative hotfixes in-cluster without a corresponding Git change.
- Standardize debugging commands, event inspection, and health checks for every workload type.
- Keep rollout and rollback procedures visible in deployment documentation.

## RBAC troubleshooting

### 401 vs 403 — diagnose first

| Code | Meaning | Root cause |
|---|---|---|
| `401 Unauthorized` | Authentication failed | Invalid, expired, or missing token; cert mismatch |
| `403 Forbidden` | Authorized identity, missing permission | Role or binding absent, wrong namespace, SA name mismatch |

These are different failure layers. Confirm identity before checking permissions.

### 401 Unauthorized

**Symptom:** Request rejected before RBAC is evaluated. Often seen in pod logs as `401` when calling the Kubernetes API or in `kubectl` as `You must be logged in`.

**Evidence to collect:**

```bash
# Confirm what identity the current context presents
kubectl auth whoami

# Inspect the projected token inside a running pod
kubectl exec -n <namespace> <pod> -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token \
  | cut -d. -f2 \
  | tr -- '-_' '+/' \
  | awk '{ pad=4-length($0)%4; if(pad<4) for(i=0;i<pad;i++) $0=$0"="; print }' \
  | base64 -d 2>/dev/null \
  | jq '{sub:.sub, exp:.exp, iss:.iss}'

# Confirm the service account exists
kubectl get serviceaccount -n <namespace> <name>
```

**Common causes and fixes:**

| Cause | Fix |
|---|---|
| Expired token (manual `kubernetes.io/service-account-token` secret) | On clusters \< 1.24, you can delete the Secret and let the token controller recreate it. On Kubernetes 1.24+, either recreate the Secret with the correct `kubernetes.io/service-account.name` and `kubernetes.io/service-account.uid` annotations, or migrate the workload to use projected service account tokens and update the pod volume mounts accordingly. |
| Service account deleted while pod is running | Restart pod; it will mount a fresh projected token |
| `kubeconfig` referencing a deleted cluster user | Re-generate kubeconfig from cloud provider (e.g. `aws eks update-kubeconfig`) |
| Certificate expired on client | Rotate the client cert via your cluster CA or re-bootstrap the node |

**Prevention:** Prefer projected service account tokens (default since Kubernetes 1.24+). Avoid manually created `kubernetes.io/service-account-token` Secrets — they do not auto-rotate and may not be auto-recreated if deleted.

---

### 403 Forbidden

**Symptom:** Pod or controller logs show `403 Forbidden` or `is forbidden: User "system:serviceaccount:<ns>:<name>" cannot <verb> resource "<resource>"`.

**Evidence to collect:**

```bash
# Simulate the exact failing request
kubectl auth can-i <verb> <resource> \
  --as=system:serviceaccount:<namespace>:<sa-name> \
  -n <namespace>

# Find all bindings that reference this service account
kubectl get rolebindings,clusterrolebindings -A -o json \
  | jq -r '
    .items[]
    | select(
        .subjects[]?
        | select(.kind=="ServiceAccount"
            and .name=="<sa-name>"
            and .namespace=="<namespace>")
      )
    | "\(.kind)/\(.metadata.namespace)/\(.metadata.name) -> \(.roleRef.name)"'

# Inspect the bound role's rules
kubectl describe clusterrole <role-name>
kubectl describe role <role-name> -n <namespace>
```

**Fix — minimal role example:**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: app-team
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: app-team
subjects:
  - kind: ServiceAccount
    name: app-controller
    namespace: app-team
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

**Validation:**

```bash
kubectl auth can-i get pods \
  --as=system:serviceaccount:app-team:app-controller \
  -n app-team
# expected: yes
```

**Rollback:** Delete the `RoleBinding`. Roles and bindings are additive — removing them cannot break running workloads (beyond revoking the access just granted).

---

### Namespace scope vs. cluster scope

| Binding type | Scope | Use when |
|---|---|---|
| `RoleBinding` → `Role` | Namespace only | Workload needs access within one namespace |
| `RoleBinding` → `ClusterRole` | Namespace only | Reuse a cluster-defined role, scoped to one namespace |
| `ClusterRoleBinding` → `ClusterRole` | All namespaces | Platform controllers or node-level access |

Prefer the narrowest scope. `ClusterRoleBinding` grants access cluster-wide — use only for controllers that genuinely need cross-namespace or node-level access.

**Common mistake:** Using `ClusterRoleBinding` when `RoleBinding` in the correct namespace was sufficient. Audit with:

```bash
kubectl get clusterrolebindings -o json \
  | jq -r '.items[] | select(.subjects[]?.kind=="ServiceAccount") | "\(.metadata.name) -> \(.roleRef.name)"'
```
