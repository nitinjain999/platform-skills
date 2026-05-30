# Demo: Kubernetes Production Review

> Status: Stable

A realistic Kubernetes Deployment that platform-skills catches before it reaches production.

## What's wrong with bad.yaml

| Finding | Severity | Risk |
|---|---|---|
| `image: latest` — unpinned tag | Critical | Non-reproducible deploys; silent rollouts |
| No `securityContext` | Critical | Container runs as root; writable filesystem |
| No `resources` limits/requests | High | OOMKill in production; noisy neighbour |
| No `readinessProbe` | High | Traffic hits the pod before the app is ready |
| Hardcoded `DATABASE_URL` with credentials | High | Secret exposed in manifest and pod spec |

## What changed in fixed.yaml

- Pinned image tag (`v1.4.2`) — reproducible, auditable
- `securityContext` at pod and container level — non-root, read-only filesystem, all capabilities dropped
- `resources.requests` and `resources.limits` — predictable scheduling
- `readinessProbe` and `livenessProbe` — safe traffic and self-healing
- Credentials moved to `secretKeyRef` — secret stays in Kubernetes Secrets
- Dedicated `serviceAccountName` — least-privilege identity

## Blast radius of bad.yaml in production

- OOMKill during traffic spike → pod restart loop → degraded availability
- Root container breakout → node compromise
- Silent image update on next deploy → unknown code in production
- Credentials in pod spec → visible in `kubectl describe pod` output

## Validation

```bash
kubectl apply --dry-run=client -f fixed.yaml
kubectl auth can-i --list --as=system:serviceaccount:production:api-server
```

## Rollback

```bash
kubectl rollout undo deployment/api-server -n production
kubectl rollout status deployment/api-server -n production
```

## Try it yourself

```text
Use $platform-skills to review this Kubernetes Deployment for production readiness:
securityContext, resources, probes, lifecycle, service account, and RBAC.
```
