---
title: Progressive Delivery
custom_edit_url: null
---

# Progressive Delivery Reference

Covers all `/platform-skills:progressive-delivery` mode logic: canary releases with Flagger on Flux, traffic shifting through Gateway API (Envoy Gateway for north-south, Linkerd for east-west), metric-based promotion and automatic rollback, and how it interacts with GitOps.

**Verified against:** Flagger 1.45.0 (chart `oci://ghcr.io/fluxcd/charts/flagger`, Canary `flagger.app/v1beta1`), Flux 2.9. Working example: `examples/progressive-delivery`.

## Ownership boundary

| Question | Authoritative skill |
|---|---|
| Canary or blue/green rollout with automatic promotion and rollback | **`/platform-skills:progressive-delivery`** |
| The Gateway, listeners and routes themselves | `/platform-skills:gateway-api` |
| Linkerd injection, mTLS, `linkerd viz` | `/platform-skills:linkerd` |
| Flux not reconciling the Deployment or the Canary | `/platform-skills:gitops` |
| Writing the Prometheus queries behind a metric | `/platform-skills:observability` |

## Why Flagger here

Flagger runs as a Flux component (published under `fluxcd/`, signed OCI artifacts), so it fits the repository's Flux layout. It drives the Gateway API `HTTPRoute` weights that Envoy Gateway and Linkerd both implement, so one Canary model covers north-south and east-west traffic. Argo Rollouts is the equivalent for Argo CD shops; it replaces the Deployment with its own `Rollout` kind, which Flagger does not.

## How a Flagger canary works

1. You commit a new image (or any pod-spec change) to the `Deployment` in Git; Flux applies it.
2. Flagger notices the change (to the pod template, or to a ConfigMap or Secret it references). It keeps serving production from `<app>-primary` (which it created from the Deployment on first adoption) and scales the target up as the canary.
3. It runs `pre-rollout` webhooks (smoke tests), then moves `stepWeight`% of traffic to the canary every `interval`, up to `maxWeight`. Webhooks of `type: bash` or `cmd` run in Flagger's loadtester, a separate chart (`loadtester` from `https://flagger.app`) installed in the app namespace; without it every rollout fails its first webhook.
4. At each step it evaluates the metrics. A failed check counts towards `threshold`; reaching it aborts, sets weight back to 0 and scales the canary down: **automatic rollback**.
5. When `maxWeight` passes, Flagger copies the canary spec to the primary and routes 100% back to the primary: **promotion**.

| Setting | Meaning | Starting value |
|---|---|---|
| `analysis.interval` | Time between steps and checks | `1m` |
| `analysis.threshold` | Failed checks before rollback | `5` |
| `analysis.stepWeight` / `maxWeight` | Traffic increment / ceiling | `10` / `50` |
| `progressDeadlineSeconds` | Rollback if the canary never becomes ready | `600` |

A full rollout takes about `maxWeight / stepWeight × interval` (5 minutes with the values above) plus promotion.

## Traffic providers

| Traffic | Flagger setting | `service.gatewayRefs` points at |
|---|---|---|
| North-south through the shared Envoy Gateway | `meshProvider: gatewayapi:v1` | The `Gateway`, with `sectionName` of the app's listener |
| East-west inside Linkerd | `meshProvider: gatewayapi:v1beta1` (as in Flagger's Linkerd tutorial) | The app's `Service` (`group: core`, `kind: Service`, `port`) |

Flagger generates the `HTTPRoute`. Remove any hand-written route for the same hostname or Service, or the two will split traffic.

## Metrics

The metric decides promotion, so it must measure the canary pods only. Linkerd's proxy metrics do that with `deployment=~"{{ target }}"` and `direction="inbound"` (see `examples/progressive-delivery/app/metrictemplates.yaml`). With an ingress-only setup, use the gateway's per-backend metrics instead; whatever the source, confirm the query returns data for the canary before relying on it. A query that returns no data fails every check and rolls back every release.

## GitOps interplay

- Flux owns the `Deployment` and `Canary` in Git; Flagger owns `<app>-primary`, `<app>-canary` Services and the generated `HTTPRoute`. Do not commit Flagger-generated objects.
- With an HPA, reference it in `autoscalerRef` so Flagger manages the primary's autoscaler too.
- `spec.revertOnDeletion: true` restores the original Deployment and routing if the Canary is deleted; set it before removing Flagger.

## Rollback

| Situation | Action |
|---|---|
| A canary fails its checks | Nothing: Flagger has already rolled traffic back to the primary. Revert or fix the commit in Git so Flux does not keep proposing it |
| A bad version was already promoted | Revert the commit in Git; the revert itself goes through a canary analysis back to the old version |
| An emergency rollback cannot wait for analysis | Set `spec.skipAnalysis: true`, revert in Git, then remove `skipAnalysis` |
| Flagger itself misbehaves | Set `spec.suspend: true` on the Canary to stop it acting; with `revertOnDeletion: true`, deleting the Canary restores plain Deployment routing |

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| Canary stuck `Progressing`, then rolled back with no traffic | Metric query returns no data | Run the MetricTemplate query in Prometheus with the canary's name |
| Every release rolls back at the first step | Smoke-test webhook failing (including no loadtester at the webhook URL), or the canary Service has no ready endpoints | Flagger events: `kubectl -n <ns> describe canary <name>` |
| Traffic never shifts | Hand-written HTTPRoute still bound to the hostname, or wrong `sectionName` | `kubectl get httproute -n <ns>` and the route's `.status.parents` |
| Canary never starts | Nothing Flagger tracks changed | An analysis starts on a change to the pod template or to a ConfigMap or Secret the pods reference |
