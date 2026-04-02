# Kubernetes Examples

This directory contains reference implementations for baseline Kubernetes platform patterns that apply across managed clusters and distributions.

## Example Areas

### 1. Namespace Baseline

Use a consistent namespace bootstrap for every team or service:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: payments
  labels:
    owner: platform-team
    environment: production
    pod-security.kubernetes.io/enforce: restricted
```

### 2. Deployment Baseline

Prefer workloads with explicit health checks and resource controls:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments-api
  namespace: payments
spec:
  replicas: 3
  selector:
    matchLabels:
      app: payments-api
  template:
    metadata:
      labels:
        app: payments-api
    spec:
      serviceAccountName: payments-api
      containers:
        - name: api
          image: ghcr.io/example/payments-api:1.2.3
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
          readinessProbe:
            httpGet:
              path: /readyz
              port: 8080
```

### 3. Network Policy Baseline

Default-deny inbound traffic and allow only explicit paths:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: payments
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

### 4. Pod Disruption Budget

Protect critical services during maintenance and node churn:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: payments-api
  namespace: payments
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: payments-api
```

## Operational Checklist

- Namespace ownership labels present
- Requests and limits defined
- Health probes defined
- ServiceAccount explicitly set
- Network policy applied
- Rollback path documented in GitOps or deployment tooling
