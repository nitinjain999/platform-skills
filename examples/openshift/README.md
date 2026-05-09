Status: Stable

# OpenShift Examples

Manifests for adapting workloads and platform components to Red Hat OpenShift constraints — Routes, tenant isolation, and SCC-compatible security contexts.

## Examples

| File | What it shows | Key patterns |
|------|--------------|-------------|
| [route.yaml](route.yaml) | OpenShift Route with edge TLS termination and HTTP→HTTPS redirect | `tls.termination: edge`, `insecureEdgeTerminationPolicy: Redirect` |
| [resource-quota.yaml](resource-quota.yaml) | ResourceQuota and LimitRange for tenant namespace isolation | CPU/memory bounds, object count limits, default container limits |

## Quick Start

```bash
# Apply tenant isolation (quota before workloads land)
oc apply -f resource-quota.yaml

# Expose a service via Route
oc apply -f route.yaml

# Verify quota usage
oc describe quota -n <namespace>

# Verify route is serving
oc get route -n <namespace>
curl -I https://$(oc get route my-app -n <namespace> -o jsonpath='{.spec.host}')
```

## SCC Compatibility

OpenShift enforces Security Context Constraints (SCC). Every container must pass the `restricted` SCC by default:

```yaml
# ✅ Works with OpenShift restricted SCC
securityContext:
  runAsNonRoot: true          # Do NOT set runAsUser to a specific UID — OpenShift assigns one
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

```yaml
# ❌ Will fail OpenShift SCC validation
securityContext:
  runAsUser: 1000             # Specific UID not allowed under restricted SCC
```

## Route TLS Termination Modes

| Mode | Where TLS terminates | Use when |
|------|---------------------|----------|
| `edge` | At the router | Default; backend receives plain HTTP |
| `passthrough` | At the pod | mTLS required to the pod |
| `reencrypt` | At router and re-encrypted to pod | Compliance requirement for in-cluster encryption |

## Tenant Isolation Pattern

Each team namespace gets:
1. `ResourceQuota` — caps total CPU, memory, and object counts
2. `LimitRange` — sets default requests/limits so pods without explicit values still have bounds
3. `NetworkPolicy` — default-deny; see [kubernetes/network-policy-default-deny.yaml](../kubernetes/network-policy-default-deny.yaml)
4. RBAC — team `edit` role on their own namespace, no cross-namespace access

## Checklist

- [ ] Containers pass `restricted` SCC: no specific `runAsUser`, no host ports, capabilities dropped
- [ ] Routes use correct TLS termination mode for the trust model
- [ ] Routes have `insecureEdgeTerminationPolicy: Redirect` to prevent plain HTTP access
- [ ] Each tenant namespace has ResourceQuota, LimitRange, and NetworkPolicy
- [ ] Operator-managed platform services are in separate namespaces from application workloads
- [ ] Platform operators installed via OLM with explicit channel and approval strategy

## See Also

- [references/openshift.md](../../references/openshift.md) — SCC-aware workload design, Routes, operators, tenancy patterns
- [examples/kubernetes/](../kubernetes/) — base Kubernetes patterns that OpenShift also supports
- `/platform-skills:debug` — structured diagnosis for OpenShift issues
