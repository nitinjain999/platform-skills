# Progressive Delivery Example

Status: Beta

Flagger canary releases for `my-app` from [examples/fluxcd/basic-monorepo](../fluxcd/basic-monorepo/): traffic shifts in 10% steps on the shared Envoy Gateway listener, and each step is checked against Linkerd's success-rate and p99 latency for the canary pods. Five failed checks roll the release back automatically.

| File | What it is |
|---|---|
| `flagger/ocirepository.yaml` | Flagger chart 1.45.0 from `oci://ghcr.io/fluxcd/charts/flagger`, signature verified by Flux (Cosign keyless) |
| `flagger/helmrelease.yaml` | Flagger with `meshProvider: gatewayapi:v1` and Linkerd's Prometheus as the metrics server |
| `app/metrictemplates.yaml` | Success rate and p99 latency from Linkerd proxy metrics (`response_total`, `response_latency_ms_bucket`) |
| `app/loadtester.yaml` | Flagger's loadtester 0.39.0 in the app namespace. It runs the Canary's smoke-test webhook; without it every rollout fails its pre-rollout check |
| `app/canary.yaml` | The Canary: attaches to `platform-gateway`'s `https-my-app` listener, 10% steps up to 50%, smoke test before any traffic moves |

Prerequisites: Flux 2.8+, the basic-monorepo Gateway, Linkerd with linkerd-viz, and the app namespace meshed (`linkerd.io/inject: enabled`). Without Linkerd, point `metricsServer` and the MetricTemplates at the Prometheus that scrapes your gateway.

When you adopt it, delete the app's own `HTTPRoute`: Flagger generates the route for the hostname and two routes would split traffic between them.

Validate the manifests:

```bash
CAT='https://raw.githubusercontent.com/datreeio/CRDs-catalog/63669a570e231d4f1f8396d229a1de512bcf0a34/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
kubeconform -strict -summary -schema-location default -schema-location "$CAT" examples/progressive-delivery/*/*.yaml
```

The full guide is `/platform-skills:progressive-delivery` and `references/progressive-delivery.md`.
