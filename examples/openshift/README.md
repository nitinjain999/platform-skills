# OpenShift Examples

This directory contains reference patterns for adapting Kubernetes workloads and platform components to Red Hat OpenShift.

## Example Areas

### 1. Route Exposure

Prefer OpenShift `Route` resources when exposing services through the platform router:

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: payments-api
  namespace: payments
spec:
  host: payments.apps.example.com
  to:
    kind: Service
    name: payments-api
  port:
    targetPort: http
  tls:
    termination: edge
```

### 2. Restricted Security Compatibility

OpenShift commonly enforces restricted execution. Validate manifests against:

- Randomized user IDs
- Non-root execution
- Writable volume requirements
- Capability drops and privilege escalation rules

Example pod security context:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

### 3. Project Quotas and Limits

Use quotas and limit ranges to isolate tenants:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: payments-quota
  namespace: payments
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
```

### 4. Operator-Centric Platform Services

Prefer Operators for core platform services that OpenShift manages well:

- Logging and observability operators
- Service mesh operators
- Certificate and ingress integrations
- GitOps operator if Argo CD is the platform standard

## Validation Checklist

- Workloads pass OpenShift SCC defaults
- Routes use the correct hostname and TLS termination model
- Operator-managed services are separated from app namespaces
- Tenant projects have explicit RBAC, quotas, and limits
