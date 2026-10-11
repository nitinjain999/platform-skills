---
name: progressive-delivery
description: Canary releases with automatic promotion and rollback using Flagger on Flux. Shifts traffic through Gateway API HTTPRoute weights (Envoy Gateway for north-south, Linkerd for east-west), gates each step on success-rate and latency metrics for the canary pods, runs smoke tests before traffic moves, and rolls back on its own when checks fail. Covers install with signed OCI charts, Canary and MetricTemplate design, GitOps ownership, and emergency rollback. Use when asked to "add canary deployments", "roll out gradually", "automatic rollback on errors", "set up Flagger", or "why did my canary roll back". Gateway and routes themselves → /platform-skills:gateway-api. Linkerd mesh issues → /platform-skills:linkerd.
argument-hint: "[install|canary|metrics|debug|rollback] [app or namespace]"
title: "Progressive Delivery Command"
sidebar_label: "progressive-delivery"
custom_edit_url: null
---

Ship a new version to a slice of real traffic first, promote it only on evidence, and roll it back without a human when the evidence says no.

Read `references/progressive-delivery.md` before responding. It holds how a Flagger analysis runs, the provider settings for Envoy Gateway and Linkerd, metric rules, GitOps ownership, rollback by situation, and troubleshooting. The working manifests are in `examples/progressive-delivery`.

**This skill is interactive by default.** With no arguments, ask how traffic reaches the app (shared Envoy Gateway, Linkerd east-west, both), where metrics come from (Linkerd viz, gateway Prometheus, other), and whether the app has an HPA, then run `canary`. Never apply resources or change a live Canary yourself.

## Mode dispatch

| Mode | What it does |
|---|---|
| `install` | Flagger via Flux from the signed OCI chart, with `meshProvider` and `metricsServer` for the user's traffic and metrics |
| `canary` | Canary and MetricTemplates for one app, from `examples/progressive-delivery`, adapted to its ports, hostname, listener and HPA |
| `metrics` | Design or fix the MetricTemplate queries so they measure the canary pods only, and prove they return data |
| `debug` | Why a canary is stuck, never starts, or always rolls back, from Flagger events and route status |
| `rollback` | The right rollback for the situation: automatic, revert in Git, `skipAnalysis`, or `suspend` |

## Mode: canary

1. Start from `examples/progressive-delivery/app/canary.yaml`. Set `targetRef`, `service.port` and `targetPort`, `hosts`, and `gatewayRefs` (the Gateway and `sectionName` for north-south; the Service for Linkerd east-west).
2. Add `autoscalerRef` when the app has an HPA.
3. Pick `interval`, `stepWeight`, `maxWeight` and `threshold` from the app's traffic: a check needs enough requests per `interval` to be meaningful; a low-traffic app needs a load-test webhook or a longer interval.
4. If the Canary has webhooks, include `examples/progressive-delivery/app/loadtester.yaml` in the app namespace; the webhook URL must name that Service.
5. Remove the app's hand-written `HTTPRoute` in the same change; say so explicitly.
6. Validate with `kubeconform -strict` against the CRD catalog, as the example README shows.

## Mode: rollback

Use the reference's rollback table. State which objects Flagger owns (primary, generated Services and HTTPRoute) and that the fix for a failed release is always a change in Git, because Flux will keep applying whatever Git says.

## Output format

Every mode ends with:

- **Changes**, as exact files and fields
- **Blast radius**, in one line (which traffic and for how long)
- **Validation**, as commands (`kubectl describe canary`, the metric query, route status)
- **Rollback**, for the situation in question
