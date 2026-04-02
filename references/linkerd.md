# Linkerd Reference

## Contents

- Scope
- Architecture
- Installation
- Mesh injection
- mTLS
- Traffic management
- Observability
- Multi-cluster
- Troubleshooting

## Scope

Use Linkerd for:

- Automatic mutual TLS between workloads without application code changes
- L7 observability: golden signals (success rate, latency, RPS) per route and deployment
- Traffic management: retries, timeouts, canary splits via HTTPRoute
- Multi-cluster service mirroring with encrypted cross-cluster traffic

Do not expect Linkerd to replace:

- Ingress controllers (Linkerd handles east-west mesh traffic, not north-south ingress)
- Network policies (Linkerd authorization policy complements, not replaces, Kubernetes NetworkPolicy)
- DNS or service discovery (Linkerd wraps existing Kubernetes DNS)

## Architecture

### Control plane

| Component | Role |
|-----------|------|
| `destination` | Resolves service endpoints, traffic policies, and route configurations |
| `identity` | Issues short-lived workload certificates (default 24h) for mTLS |
| `proxy-injector` | Webhook that injects the sidecar proxy into pods at admission time |

### Data plane

Each meshed pod gets a `linkerd-proxy` sidecar (written in Rust). The proxy intercepts all inbound and outbound traffic transparently using `iptables` rules added by the `linkerd-init` init container.

The proxy handles:
- mTLS negotiation and certificate validation
- Retries, timeouts, and circuit breaking
- Metrics export on `:4191/metrics` (scraped by Prometheus)

## Installation

### Prerequisites

- Kubernetes 1.22+
- `linkerd` CLI matching the control plane version
- A trust anchor certificate (self-signed or cert-manager)

### Control plane install

```bash
# Pre-flight checks
linkerd check --pre

# Install CRDs
linkerd install --crds | kubectl apply -f -

# Install control plane
linkerd install | kubectl apply -f -

# Verify all components are healthy
linkerd check
```

### Using cert-manager for the identity CA

Back the Linkerd identity issuer with cert-manager so the intermediate CA rotates automatically:

```yaml
# Certificate issued by cert-manager for Linkerd identity
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: linkerd-identity-issuer
  namespace: linkerd
spec:
  secretName: linkerd-identity-issuer
  duration: 48h
  renewBefore: 25h
  issuerRef:
    name: linkerd-trust-anchor    # ClusterIssuer backed by your root CA
    kind: ClusterIssuer
  commonName: identity.linkerd.cluster.local
  dnsNames:
    - identity.linkerd.cluster.local
  isCA: true
  privateKey:
    algorithm: ECDSA
  usages:
    - cert sign
    - crl sign
    - server auth
    - client auth
```

Then install Linkerd pointing at cert-manager's output:

```bash
linkerd install \
  --identity-external-issuer \
  | kubectl apply -f -
```

### Linkerd Viz (observability extension)

```bash
linkerd viz install | kubectl apply -f -
linkerd viz check
```

## Mesh injection

### Namespace-level injection

Annotate a namespace to auto-inject the proxy into every new pod:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: payments
  annotations:
    linkerd.io/inject: enabled
```

Existing pods are not re-injected automatically. Rollout the deployment after annotating:

```bash
kubectl rollout restart deployment -n payments
```

### Pod-level override

Opt a specific pod out of injection inside an injected namespace:

```yaml
spec:
  template:
    metadata:
      annotations:
        linkerd.io/inject: disabled
```

### Verify injection

```bash
# Check which pods in a namespace are meshed
linkerd check --namespace payments

# Show proxy version and injection status per pod
kubectl get pods -n payments -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.linkerd\.io/inject}{"\n"}{end}'
```

### What not to inject

- `kube-system` and `kube-public` — control plane components will break
- Linkerd's own `linkerd` namespace — already meshed differently
- Jobs and CronJobs that use `hostNetwork: true`
- Daemonsets that must run before the proxy is ready (e.g., CNI plugins)

## mTLS

Linkerd automatically establishes mTLS between all meshed pods. No certificate management or application changes are needed.

### How it works

1. `proxy-injector` injects the sidecar at pod admission
2. On startup, the proxy fetches a short-lived SPIFFE-compatible certificate from the `identity` component
3. The certificate encodes the pod's Kubernetes ServiceAccount as the identity
4. All proxies validate peer certificates before forwarding traffic

### Verify mTLS is active

```bash
# Show secured/unsecured edges between deployments
linkerd viz edges deployment -n payments

# Output includes: SRC, DST, SECURED (yes/no)
# If a pod is unmeshed, the edge shows "no" — traffic is plaintext
```

### Authorization policy

Restrict which identities can call a service (replaces or supplements NetworkPolicy):

```yaml
apiVersion: policy.linkerd.io/v1beta3
kind: Server
metadata:
  name: payments-api
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: payments-api
  port: 8080
  proxyProtocol: HTTP/2
---
apiVersion: policy.linkerd.io/v1beta3
kind: AuthorizationPolicy
metadata:
  name: payments-api-allow-checkout
  namespace: payments
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: payments-api
  requiredAuthenticationRefs:
    - name: checkout-sa
      kind: MeshTLSAuthentication
      group: policy.linkerd.io
---
apiVersion: policy.linkerd.io/v1beta3
kind: MeshTLSAuthentication
metadata:
  name: checkout-sa
  namespace: payments
spec:
  identities:
    - "checkout.payments.serviceaccount.identity.linkerd.cluster.local"
```

## Traffic management

Linkerd uses the Kubernetes Gateway API (`HTTPRoute`) for traffic splitting and routing rules.

### Canary traffic split

Route 90% of traffic to stable, 10% to canary:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: payments-api-canary
  namespace: payments
spec:
  parentRefs:
    - name: payments-api
      kind: Service
      group: core
      port: 8080
  rules:
    - backendRefs:
        - name: payments-api-stable
          port: 8080
          weight: 90
        - name: payments-api-canary
          port: 8080
          weight: 10
```

### Retries

```yaml
apiVersion: policy.linkerd.io/v1alpha1
kind: HTTPLocalRateLimitPolicy
metadata:
  name: payments-retry
  namespace: payments
```

For retries, use annotations on the HTTPRoute or configure via the Linkerd `retry` annotation on the Service:

```yaml
# Retry on 5xx responses, up to 2 retries
metadata:
  annotations:
    retry.linkerd.io/http: "5xx"
    retry.linkerd.io/limit: "2"
```

### Timeouts

```yaml
# Per-route timeout via HTTPRoute
spec:
  rules:
    - timeouts:
        request: 10s
        backendRequest: 5s
```

## Observability

### Golden signals per deployment

```bash
# Success rate, RPS, and latency for all deployments in a namespace
linkerd viz stat deploy -n payments

# Drill into a specific deployment
linkerd viz stat deploy/payments-api -n payments

# Per-route breakdown
linkerd viz stat httproute -n payments
```

### Live request tracing

```bash
# Tap live traffic to a deployment (shows headers, status codes, latency)
linkerd viz tap deploy/payments-api -n payments

# Filter to specific path
linkerd viz tap deploy/payments-api -n payments --path /api/v1/charge
```

### Prometheus integration

Linkerd proxies expose metrics on port `4191`. Scrape them with a `PodMonitor` (Prometheus Operator):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: linkerd-proxy
  namespace: monitoring
spec:
  namespaceSelector:
    any: true
  podMetricsEndpoints:
    - port: linkerd-admin
      path: /metrics
  selector:
    matchLabels:
      linkerd.io/control-plane-ns: linkerd
```

Key metrics to alert on:

| Metric | Alert threshold |
|--------|----------------|
| `request_total{direction="inbound", classification="failure"}` | > 1% of total |
| `response_latency_ms_bucket{le="1000"}` | p99 > 1000ms |
| `tcp_open_connections` | sustained spike vs. baseline |

## Multi-cluster

Linkerd multi-cluster mirrors services from one cluster into another using a gateway and a `ServiceMirror` controller.

### Requirements

- Both clusters must share the same trust anchor (root CA)
- Clusters must have network connectivity to each other's gateway LoadBalancer IPs

### Link clusters

On the target cluster (where the service lives):

```bash
# Install multi-cluster extension
linkerd multicluster install | kubectl apply -f -
linkerd multicluster check

# Generate link credentials for the source cluster
linkerd multicluster link --cluster-name production > link-production.yaml
```

On the source cluster (where you want to consume the service):

```bash
kubectl apply -f link-production.yaml
linkerd multicluster check
```

### Mirror a service

Label the service in the target cluster to make it available cross-cluster:

```yaml
metadata:
  labels:
    mirror.linkerd.io/exported: "true"
```

The `ServiceMirror` controller creates a mirrored service in the source cluster named `<service>-<cluster-name>` (e.g., `payments-api-production`). Traffic to that service is tunnelled over mTLS to the target cluster's gateway.

### Verify mirroring

```bash
# On source cluster — should see mirrored services
kubectl get svc -n payments | grep "production"

# Check mirroring is healthy
linkerd multicluster gateways
```

## Troubleshooting

### Structure

For every Linkerd issue: identify the layer (control plane / data plane / policy / multi-cluster), collect evidence, form a hypothesis, then fix.

---

**Symptom:** Pods not getting proxies injected

Evidence to collect:
```bash
kubectl describe namespace <ns> | grep -i inject
kubectl get mutatingwebhookconfigurations linkerd-proxy-injector -o yaml | grep -A5 namespaceSelector
linkerd check
```

Likely causes:
- Namespace missing `linkerd.io/inject: enabled` annotation
- Pod has `linkerd.io/inject: disabled` override
- `proxy-injector` webhook is failing — check `linkerd check` output

---

**Symptom:** mTLS edges showing `no` (plaintext)

Evidence to collect:
```bash
linkerd viz edges deployment -n <namespace>
kubectl get pods -n <namespace> -o wide  # check both src and dst are meshed
linkerd check --namespace <namespace>
```

Likely causes:
- One side of the connection is not meshed (check both pods)
- Pod was running before namespace was annotated and hasn't been rolled

Fix:
```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

---

**Symptom:** `linkerd check` reports certificate expiry or identity errors

Evidence to collect:
```bash
linkerd check
kubectl get secret linkerd-identity-issuer -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

Likely causes:
- Issuer certificate expired (cert-manager rotation failed)
- Trust anchor mismatch after manual rotation

Fix: rotate using cert-manager renewal or `linkerd upgrade --identity-external-issuer`.

---

**Symptom:** High latency after enabling Linkerd

Evidence to collect:
```bash
linkerd viz stat deploy -n <namespace>
linkerd viz tap deploy/<name> --max-rps 10
kubectl top pods -n <namespace>  # check proxy CPU
```

Likely causes:
- Proxy CPU limit too low (default is 1 CPU) — under heavy load the proxy queues requests
- Retry storms amplifying load

Fix: increase proxy resource limits via annotation:

```yaml
annotations:
  config.linkerd.io/proxy-cpu-limit: "2"
  config.linkerd.io/proxy-memory-limit: "256Mi"
```

---

**Symptom:** Multi-cluster mirrored service unreachable

Evidence to collect:
```bash
linkerd multicluster gateways          # check gateway status
kubectl get svc -n linkerd-multicluster  # check gateway LB IP is assigned
linkerd check --multicluster
```

Likely causes:
- Gateway LoadBalancer IP not yet assigned
- Firewall blocking port 4143 between cluster networks
- Trust anchor mismatch between clusters
