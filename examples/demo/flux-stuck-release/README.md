# Demo: Flux Stuck Release

> Status: Stable

A Flux HelmRelease that goes NotReady and stays there. Platform-skills identifies why it's stuck and what to fix before the next deploy.

## What's wrong with bad.yaml

| Finding | Severity | Risk |
|---|---|---|
| `version: "*"` — unpinned chart | Critical | Silent major upgrades; non-reproducible clusters |
| No `dependsOn` | High | HelmRelease deploys before cert-manager CRDs exist → CrashLoopBackOff |
| `interval: 1h` — too long | Medium | Changes take up to 1 hour to reconcile |
| No `timeout` | Medium | Stuck install blocks other Flux reconciliations |
| No `remediation` | Medium | Failed install retries forever without rollback |
| `replicaCount: 1` | Medium | Single point of failure during node drain |

## What changed in fixed.yaml

- Pinned chart version `4.10.1` — upgrade is an explicit PR decision
- `dependsOn: cert-manager` — ensures CRDs exist before ingress deploys
- `interval: 10m` — changes reconcile in minutes, not hours
- `timeout: 5m` — fail fast, unblock other reconciliations
- `install.remediation.retries: 3` + `upgrade.remediation.remediateLastFailure: true` — automatic rollback on failure
- `replicaCount: 2` — survives node drain without downtime

## Diagnosing a stuck release

```bash
flux get helmrelease nginx-ingress -n ingress-system
flux logs --kind HelmRelease --name nginx-ingress --namespace ingress-system
kubectl describe helmrelease nginx-ingress -n ingress-system
```

## Force reconcile after fix

```bash
flux reconcile helmrelease nginx-ingress -n ingress-system --with-source
flux get helmrelease nginx-ingress -n ingress-system --watch
```

## Try it yourself

```text
Use $platform-skills to debug this Flux HelmRelease that is stuck NotReady.
Start with evidence collection, then root cause, fix, validation, and rollback.
```
