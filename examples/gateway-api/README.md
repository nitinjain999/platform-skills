# Gateway API Migration Example

Status: Stable

A before-and-after pair for moving one ingress-nginx `Ingress` to Gateway API on Envoy Gateway. It shows what translates automatically, what needs a decision, and what does not port at all.

**Why migrate:** ingress-nginx best-effort maintenance ended in March 2026. Existing installs keep working, but there are no further releases, bug fixes or security fixes. Gateway API is the Kubernetes-recommended successor.

For the full cluster layout (controllers, shared Gateway, cert-manager, Flux layering) see [examples/fluxcd/basic-monorepo](../fluxcd/basic-monorepo/). For the guided workflow run `/platform-skills:gateway-api`.

## Files

| File | What it shows |
|---|---|
| [before/ingress.yaml](before/ingress.yaml) | An ingress-nginx `Ingress` with TLS, a timeout, a source-CIDR allowlist and a `configuration-snippet` |
| [after/httproute.yaml](after/httproute.yaml) | The portable equivalent: `HTTPRoute` with path match, response header filter and timeouts |
| [after/securitypolicy.yaml](after/securitypolicy.yaml) | The CIDR allowlist as an Envoy Gateway `SecurityPolicy`. Implementation-specific |
| [gateway-api-validate.sh](gateway-api-validate.sh) | Validates this example and the Flux monorepo |

## Annotation by annotation

| ingress-nginx annotation | Gateway API result | Portable? |
|---|---|---|
| `cert-manager.io/cluster-issuer` | Moves to the **Gateway**. The route carries no TLS | Yes |
| `proxy-read-timeout: "60"` | `rules[].timeouts.backendRequest: 60s` | Yes. Semantics differ slightly; test under load |
| `whitelist-source-range` | `SecurityPolicy` `authorization.rules[].principal.clientCIDRs` | No. Each implementation has its own policy kind |
| `configuration-snippet` | Rewritten by hand as a `ResponseHeaderModifier` filter | Partly. Raw nginx config never translates |

Treat every annotation that ingress2gateway warns about as a blocking finding. A dropped snippet is a silent behaviour change in production.

## Converting your own Ingresses

```bash
# Install ingress2gateway v1.2.0 (brew install ingress2gateway, or the release binary)
ingress2gateway print --providers=ingress-nginx --emitter=envoy-gateway \
  --input-file before/ingress.yaml > converted.yaml

# Read from the live cluster instead, every namespace
ingress2gateway print --providers=ingress-nginx --emitter=envoy-gateway -A > converted.yaml
```

Review `converted.yaml` before applying it. The tool emits its own `Gateway` objects; in a shared-Gateway model, delete them and point each route's `parentRefs` at `platform-gateway`.

## Validate

```bash
bash examples/gateway-api/gateway-api-validate.sh
```

Checks that every Flux overlay builds, that every manifest passes `kubeconform -strict` against the CRD catalog (when kubeconform is installed), that no manifest still depends on ingress-nginx, and that every Ingress host survives into the HTTPRoute.

## Rollback

During migration both controllers run side by side, each with its own load balancer address. Rollback is a DNS change back to the ingress-nginx address, not a redeploy. Keep ingress-nginx running until the new path has served production traffic for a full soak period (at least one business cycle). Only then delete it.
