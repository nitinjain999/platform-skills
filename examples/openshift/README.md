# OpenShift Examples

Manifests for adapting workloads and platform components to Red Hat OpenShift constraints.

Status: committed manifest snippets for the handbook. They illustrate OpenShift-specific adaptations rather than a complete standalone repo.

## Files

| File | What it shows |
|---|---|
| [route.yaml](route.yaml) | OpenShift Route with edge TLS termination and HTTP redirect |
| [resource-quota.yaml](resource-quota.yaml) | ResourceQuota and LimitRange for tenant namespace isolation |

## Usage

```bash
oc apply -f route.yaml
oc apply -f resource-quota.yaml
```

## OpenShift Security Compatibility

OpenShift enforces restricted execution by default. Every container spec must pass SCC validation:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

See [examples/kubernetes/deployment-baseline.yaml](../kubernetes/deployment-baseline.yaml) for a full deployment with this applied.

## Checklist

- Workloads pass OpenShift SCC defaults (no root, no privilege escalation, no host ports)
- Routes use the correct hostname and TLS termination model
- Operator-managed platform services are separated from application namespaces
- Tenant projects have explicit RBAC, quotas, and limit ranges
