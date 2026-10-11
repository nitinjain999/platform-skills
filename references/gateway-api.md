---
title: Gateway API
custom_edit_url: null
---

# Gateway API Reference

Covers all `/platform-skills:gateway-api` mode logic: why and when to leave ingress-nginx, choosing an implementation, the ownership model, translating ingress-nginx annotations, cert-manager integration, Flux layering, a parallel-run cutover, validation, rollback and troubleshooting.

**Verified against:** Gateway API v1.6.1 (standard channel), Envoy Gateway v1.9.2, cert-manager v1.21.2, ingress2gateway v1.2.0, Flux v2.9. Version-sensitive claims are marked inline.

## Contents

- Why migrate
- Ownership boundary
- Choosing an implementation
- Ownership model
- CRD channel and lifecycle
- Translating ingress-nginx
- TLS with cert-manager
- Flux layering
- Migration path
- Validation
- Rollback
- Troubleshooting
- Common mistakes

## Why migrate

> **ingress-nginx is retired.** Best-effort maintenance ended in March 2026. Since then there are no releases, no bug fixes and no fixes for security vulnerabilities. Existing deployments keep running and the install artifacts stay available, so nothing breaks on day one. The risk grows with every CVE that will never be patched.

| Situation | Recommendation |
|---|---|
| New cluster or new service | Gateway API from the start. Never install ingress-nginx for new work |
| ingress-nginx in production, internet-facing | Plan the migration now. Unpatched CVEs on an edge proxy are the highest-exposure case |
| ingress-nginx internal-only, low change rate | Migrate on the next platform upgrade cycle. Keep the controller's network exposure minimal until then |
| Heavy use of `configuration-snippet` / `server-snippet` | Inventory first. Snippets never translate; each one is a manual design decision |

The `networking.k8s.io/v1` **Ingress API is not retired**. Only the ingress-nginx controller is. Charts that offer an optional `Ingress` template can keep it, but the handbook default is an `HTTPRoute`.

## Ownership boundary

| Question | Authoritative command |
|---|---|
| "Move my Ingresses to Gateway API", "which Gateway controller?", "why is my HTTPRoute not attached?" | **`/platform-skills:gateway-api`** |
| Flux reconciliation of the Gateway layers is stuck | `/platform-skills:gitops debug` |
| Mesh-internal (east-west) traffic splits with HTTPRoute | `/platform-skills:linkerd` |
| NetworkPolicy and namespace hardening around the proxies | `/platform-skills:kubernetes` |
| Certificates for things other than Gateway listeners | `/platform-skills:secrets` |

Gateway API covers north-south traffic (into the cluster) here. Linkerd also consumes `HTTPRoute` for east-west routing; that is a different parent (a Service, not a Gateway) and is out of scope.

## Choosing an implementation

| Implementation | Fits when | Watch out for |
|---|---|---|
| **Envoy Gateway** (handbook default) | You want a dedicated, CNI-independent edge proxy with an open-source, no-licence data plane (Envoy) | Policies beyond the core spec (rate limit, auth, IP allowlists) are Envoy Gateway CRDs and do not port |
| Cilium Gateway API | Cilium is already your CNI | Requires Cilium's kube-proxy replacement; couples ingress upgrades to CNI upgrades |
| Istio | Istio is already your mesh | Running Istio only for ingress is a lot of control plane for one job |
| NGINX Gateway Fabric | The team knows nginx and wants an nginx data plane | A different project from ingress-nginx: no annotation compatibility |
| AWS Load Balancer Controller | You want ALB/NLB to be the data plane on EKS | Feature set follows ALB/NLB capabilities; check the support level in your controller version's release notes |

Pick by **who already operates what**, not by feature lists. Every option implements the core `HTTPRoute` the same way. The differences live in the extension policies, which you should minimise.

## Ownership model

Gateway API splits ingress into roles. Map them to teams explicitly.

| Object | Owner | Typical namespace | Changes when |
|---|---|---|---|
| `GatewayClass` (+ implementation parameters such as `EnvoyProxy`) | Platform team | cluster-scoped | Controller or data-plane sizing changes |
| `Gateway` and its listeners, TLS certificates | Platform team | `envoy-gateway-system` | A new public hostname or port |
| `HTTPRoute` / `GRPCRoute` | App team | the app's namespace | Paths, backends, headers, timeouts |
| `ReferenceGrant` | Owner of the **target** namespace | target namespace | A route must reach a Service in another namespace |

Restrict which namespaces may attach to a listener. `from: All` on a shared HTTPS listener lets any namespace claim any path on that hostname.

```yaml
# ❌ Any namespace can attach to the production hostname
allowedRoutes:
  namespaces:
    from: All

# ✅ Namespaces opt in with a label the platform team controls
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        gateway-access: "true"
```

Protect the opt-in label itself: if app teams can label their own namespaces, the selector is decoration. Enforce it with admission policy (`/platform-skills:kyverno`) or keep namespace creation in the platform repo.

## CRD channel and lifecycle

Gateway API CRDs ship in two channels. **Standard** holds GA and beta fields. **Experimental** adds alpha fields and resources.

| Decision | Recommendation | Reason |
|---|---|---|
| Channel | Standard | Experimental fields can change incompatibly between minor versions |
| Who installs the CRDs | One owner, separate from the controller | Two charts installing the same CRDs fight on every upgrade |
| How they are applied | Plain manifests (Flux `Kustomization` or `kubectl apply --server-side`), not a Helm release | The CRDs are multi-megabyte; a Helm release stores chart and manifest in a Secret capped at 1 MiB |
| Deletion policy | Never garbage-collected: Flux `prune: false` + `deletionPolicy: Orphan` | Deleting a CRD deletes every Gateway and HTTPRoute in the cluster |

**Envoy Gateway v1.9.2 specifics:**

- The controller chart (`oci://docker.io/envoyproxy/gateway-helm`) bundles **experimental**-channel Gateway API CRDs by default (`crds.enabled: true`).
- It also installs a ValidatingAdmissionPolicy that rejects experimental CRDs on top of standard ones. On a cluster that already has standard-channel CRDs, for example from another controller or a managed platform, the default install fails.
- Do not `helm install` the separate CRD chart (`gateway-crds-helm`) either. Its README says to `helm template … | kubectl apply --server-side` instead, because of a Helm limitation with large CRDs in `templates/`: the EnvoyProxy CRD alone is about 1.4 MB, and the rendered set is about 3.7 MB.
- Apply plain CRDs instead: the Gateway API standard channel from `kubernetes-sigs/gateway-api` (`config/crd/standard` at the pinned tag), and the Envoy Gateway CRDs from the controller chart's own `charts/crds/crds/generated/` directory, which holds untemplated files. Set `crds.enabled: false` on the controller chart.
- The controller detects which optional CRDs exist and skips the ones that are missing, so the standard channel is enough.

```yaml
# Flux: one Kustomization per CRD source, never pruned, never deleted with the Kustomization
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gateway-api
  namespace: flux-system
spec:
  interval: 12h
  url: https://github.com/kubernetes-sigs/gateway-api
  ref:
    tag: v1.6.1
  sparseCheckout:
    - config/crd/standard
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: gateway-api-crds
  namespace: flux-system
spec:
  interval: 1h
  sourceRef:
    kind: GitRepository
    name: gateway-api
  path: ./config/crd/standard
  prune: false              # removing a CRD from the source never deletes it
  deletionPolicy: Orphan    # deleting this Kustomization never deletes the CRDs
  wait: true
```

The Envoy Gateway CRDs follow the same shape, sourced from an `OCIRepository` of `oci://docker.io/envoyproxy/gateway-helm` with `layerSelector.operation: extract` and `path: ./gateway-helm/charts/crds/crds/generated`. Full working version: `examples/fluxcd/basic-monorepo/clusters/production/gateway-crds.yaml`.

**Blast radius of a CRD upgrade:** cluster-wide. Every Gateway API consumer (other controllers, Linkerd routes, cert-manager) reads the same CRDs. Upgrade them in their own PR, after checking every consumer supports the new bundle version.

## Translating ingress-nginx

Use [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway) v1.2.0 for the mechanical part.

```bash
# Every Ingress of class "nginx" in every namespace, Envoy Gateway extensions included
ingress2gateway print --providers=ingress-nginx --emitter=envoy-gateway -A > converted.yaml

# From files instead of the cluster
ingress2gateway print --providers=ingress-nginx --input-file ingress.yaml

# A non-default ingress class name
ingress2gateway print --providers=ingress-nginx --ingress-nginx-ingress-class=internal -A
```

| Flag | Purpose |
|---|---|
| `--providers` | Required. `ingress-nginx` for this migration |
| `--emitter` | `standard` (default, core Gateway API only) or `envoy-gateway`, `kgateway`, `agentgateway` and others for implementation extensions |
| `-A` / `-n` | All namespaces / one namespace |
| `--input-file` | Read manifests instead of the cluster. Repeatable |
| `--allow-experimental-gw-api` | Include experimental fields. Leave off on a standard-channel cluster |

**Every warning the tool prints is a blocking finding.** It means an annotation was recognised and dropped, which is a silent production behaviour change.

### Annotation coverage (ingress2gateway v1.2.0, ingress-nginx provider)

| Area | Annotations | Result |
|---|---|---|
| TLS redirect | `ssl-redirect` | Default 308 redirect for TLS Ingresses is generated; `ssl-redirect: "false"` disables it |
| Redirects | `permanent-redirect`, `temporal-redirect`, `*-redirect-code`, `app-root` | `RequestRedirect` filter |
| Rewrites | `rewrite-target`, `x-forwarded-prefix` | `URLRewrite` `ReplaceFullPath`. **Capture groups (`$1`) are not supported** |
| Headers | `upstream-vhost`, `connection-proxy-header` | `RequestHeaderModifier` |
| Timeouts | `proxy-connect-timeout`, `proxy-send-timeout`, `proxy-read-timeout` | Route timeouts |
| Body size | `proxy-body-size`, `client-body-buffer-size` | Converted to resource quantities |
| Canary | `canary`, `canary-weight`, `canary-weight-total`, `canary-by-header`, `canary-by-header-value` | Weighted backends / header matches |
| Backend protocol | `backend-protocol` | `GRPC`/`GRPCS` become `GRPCRoute`; `HTTPS`/`GRPCS` create `BackendTLSPolicy` |
| Regex | `use-regex` | `PathMatchRegularExpression` |
| CORS | `enable-cors`, `cors-*` | CORS configuration |
| IP control | `whitelist-source-range`, `denylist-source-range` | Implementation-specific (Envoy Gateway `SecurityPolicy`) |
| Backend TLS | `proxy-ssl-verify`, `proxy-ssl-secret`, `proxy-ssl-name`, `proxy-ssl-server-name` | `BackendTLSPolicy` |
| Passthrough | `ssl-passthrough` | `TLSRoute` plus a `Passthrough` listener |
| **Warned, not converted** | `canary-by-header-pattern`, `canary-by-cookie`, `proxy-redirect-from/to`, `custom-headers`, `proxy-ssl-verify-depth`, `proxy-ssl-protocols` | Manual decision |
| **Not recognised** | `configuration-snippet`, `server-snippet`, auth annotations, rate limiting | Manual decision. Grep for them before you start |

```bash
# Inventory annotations across the cluster before converting anything
kubectl get ingress -A -o json \
  | jq -r '.items[] | .metadata.annotations // {} | keys[]' \
  | grep '^nginx.ingress.kubernetes.io/' | sort | uniq -c | sort -rn
```

### After conversion

ingress2gateway emits its own `Gateway` objects alongside the routes. In the shared-Gateway model:

1. Delete the generated `Gateway` objects.
2. Point every route's `parentRefs` at the platform Gateway and the right `sectionName`.
3. Move TLS from the route side to a Gateway listener (one HTTPS listener per hostname when cert-manager issues the certificate).
4. Label each app namespace that needs to attach.

## TLS with cert-manager

cert-manager v1.15+ issues certificates for Gateway listeners. Enable it explicitly:

```yaml
# cert-manager Helm values (v1.21.2)
config:
  apiVersion: controller.config.cert-manager.io/v1alpha1
  kind: ControllerConfiguration
  gatewayAPI:
    enabled: true   # enableGatewayAPI is the deprecated spelling
```

| Requirement | Detail |
|---|---|
| Annotation | `cert-manager.io/cluster-issuer` or `cert-manager.io/issuer` on the **Gateway** |
| Listener | Non-empty `hostname`, `tls.mode: Terminate` (Passthrough is not supported), a `certificateRefs` Secret name |
| Ordering | Gateway API CRDs must exist **before** cert-manager starts. Otherwise restart the cert-manager Deployment |
| HTTP-01 | Use the `gatewayHTTPRoute` solver with `parentRefs` to the port-80 listener |

```yaml
solvers:
  - http01:
      gatewayHTTPRoute:
        parentRefs:
          - name: platform-gateway
            namespace: envoy-gateway-system
            kind: Gateway
            sectionName: http
```

The solver's challenge route uses an `Exact` path match, so a catch-all HTTPS redirect on the same listener does not block issuance.

**Wildcards:** one listener per hostname scales poorly past a few dozen hostnames. A wildcard listener (`*.example.com`) needs DNS-01, which needs DNS-provider credentials in cluster. That is a security trade-off, not a free upgrade.

## Flux layering

A Gateway cannot be dry-run until its CRDs exist, so Gateway objects cannot live in the same Kustomization that installs the controller.

```
gateway-api-crds        → Gateway API standard CRDs (plain manifests, never pruned)
envoy-gateway-crds      → Envoy Gateway CRDs (plain manifests, never pruned)
infrastructure          → envoy-gateway, cert-manager (HelmReleases); dependsOn both CRD layers
infrastructure-configs  → GatewayClass, EnvoyProxy, Gateway, redirect, ClusterIssuer
apps                    → HTTPRoute per app
```

Gateway has no `Ready` condition, so `wait: true` alone reports it healthy before Envoy has an address. Add a CEL health check on `Programmed`:

```yaml
healthCheckExprs:
  - apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    failed: status.conditions.exists(e, e.type == 'Accepted' && e.status == 'False')
    current: status.conditions.exists(e, e.type == 'Programmed' && e.status == 'True')
```

Expressions evaluate against the resource itself: write `status.conditions`, not `object.status.conditions`.

`Programmed=True` needs a LoadBalancer address. On kind or bare metal without MetalLB the layer times out and blocks `apps`. That is the correct signal, not a bug to suppress.

Working example: [examples/fluxcd/basic-monorepo](../examples/fluxcd/basic-monorepo/).

## Migration path

Run both controllers side by side. Each has its own load balancer address, so traffic moves by DNS, and rollback is a DNS change.

| Phase | Action | Exit criteria |
|---|---|---|
| 1. Inventory | List Ingresses, ingress classes and annotations; flag snippets and auth | Every annotation has an owner and a decision |
| 2. Install | CRDs (standard), controller, GatewayClass, Gateway, cert-manager Gateway support | Gateway `Programmed=True`; certificates `Ready` |
| 3. Convert | ingress2gateway, then review; one namespace at a time | Every route `Accepted=True` and `ResolvedRefs=True` |
| 4. Shadow test | Hit the new address directly with the production `Host` header | Same status codes, headers and latency as the old path |
| 5. Cutover | Lower DNS TTL in advance; switch per hostname, lowest risk first | Error rate and p99 latency within SLO for the soak period |
| 6. Soak | Keep ingress-nginx running and serving the old address | At least one full business cycle without regression |
| 7. Decommission | Delete Ingress objects, then the ingress-nginx release and its load balancer | No traffic on the old address for the whole soak |

```bash
# Phase 4: test the new path without touching DNS.
# The Gateway address can be an IP or a hostname (cloud LBs often publish a DNS
# name). --connect-to accepts either and keeps the URL host for Host and TLS SNI;
# --resolve only accepts an IP and fails to parse a hostname.
NEW_ADDR=$(kubectl get gateway platform-gateway -n envoy-gateway-system -o jsonpath='{.status.addresses[0].value}')
curl -sS -o /dev/null -w '%{http_code} %{time_total}\n' \
  --connect-to payments.example.com:443:"$NEW_ADDR":443 https://payments.example.com/api/health
```

**Blast radius per phase:** phases 1 to 4 change nothing users see. Phase 5 moves one hostname at a time. Phase 7 is the only irreversible step; never combine it with phase 5 in one change.

## Validation

```bash
# Gateway accepted and programmed, with an address
kubectl get gateway -A
# Every route attached to every parent
kubectl get httproute -A -o json | jq -r '.items[] | .metadata.namespace + "/" + .metadata.name + ": " +
  ([.status.parents[]?.conditions[]? | select(.status != "True") | .type + "=" + .reason] | join(", "))'
# Certificates issued for every HTTPS listener
kubectl get certificate -A
# Flux layers healthy, in order
flux get kustomizations
# Repository examples
bash examples/gateway-api/gateway-api-validate.sh
```

An empty list after the colon in the route check means every condition is `True`.

## Rollback

| Stage reached | Rollback | Time to recover |
|---|---|---|
| Before DNS cutover | Delete the new routes; nothing user-facing changed | Immediate |
| After cutover, ingress-nginx still running | Point DNS back at the ingress-nginx address | DNS TTL (lower it to 60s before cutover) |
| After decommission | Reinstall ingress-nginx from the last Git revision; Flux re-applies the Ingress objects | Minutes to tens of minutes, plus DNS. Avoid by not decommissioning early |
| Bad CRD upgrade | Revert the CRD source tag in Git. With `prune: false` the revert never deletes a CRD | One reconcile interval |

Never roll back by deleting a CRD or the Kustomization that applies them. `deletionPolicy: Orphan` keeps the CRDs if the Kustomization goes, but a CRD deleted by hand takes every route in the cluster with it.

## Troubleshooting

| Symptom | Layer | Likely cause | Evidence | Fix |
|---|---|---|---|---|
| Route `Accepted=False`, `NotAllowedByListeners` | Runtime | Namespace not labelled, or wrong `sectionName` | `kubectl get ns <ns> --show-labels`; route `.status.parents` | Label the namespace or fix `sectionName` |
| Route `Accepted=False`, `NoMatchingListenerHostname` | Runtime | Route hostname not covered by the listener hostname | Gateway listeners vs route `hostnames` | Add a listener or align hostnames |
| Route `ResolvedRefs=False`, `BackendNotFound` | Runtime | Wrong Service name or port | `kubectl get svc -n <ns>` | Use the Service name and **port number** |
| Route `ResolvedRefs=False`, `RefNotPermitted` | Runtime | Cross-namespace backend without a `ReferenceGrant` | Backend namespace | Add a `ReferenceGrant` in the backend's namespace |
| Gateway `Programmed=False`, `AddressNotAssigned` | Runtime | No LoadBalancer implementation | `kubectl get svc -n envoy-gateway-system` stuck `<pending>` | Install one, or use a NodePort `EnvoyProxy` locally |
| No Certificate for the Gateway | Reconciliation | cert-manager started before the CRDs; Gateway support off; listener missing `hostname` | cert-manager logs; `kubectl get certificate -n envoy-gateway-system` | Restart cert-manager; set `config.gatewayAPI.enabled: true`; add the hostname |
| `infrastructure-configs` dry-run fails `no matches for kind "Gateway"` | Reconciliation | Configs layer does not depend on the CRD layer | `flux get kustomizations` | `dependsOn: infrastructure` |
| Controller install fails on a ValidatingAdmissionPolicy | Chart rendering | Experimental CRDs over existing standard CRDs | Helm error mentions `safe-upgrades.gateway.networking.k8s.io` | Apply standard-channel CRDs as plain manifests; `crds.enabled: false` on the controller |
| Behaviour differs after cutover | Runtime | A dropped annotation or snippet | ingress2gateway warnings; annotation inventory | Re-express it as a filter or policy, or roll back DNS |

## Common mistakes

- **Treating ingress2gateway output as final.** It warns and continues. Every warning is a behaviour change.
- **`from: All` on a shared listener.** Any namespace can then serve any path on a production hostname.
- **Leaving the controller chart's bundled CRDs on.** You get the experimental channel cluster-wide without deciding to.
- **Decommissioning ingress-nginx in the cutover change.** It removes the only fast rollback.
- **A PodDisruptionBudget of `minAvailable: 1` on a single proxy replica.** It blocks every node drain. Scale to two or drop the PDB.
- **Expecting snippets to port.** Raw nginx config has no Gateway API equivalent by design.

## Cross-references

- `references/fluxcd-kustomization.md`: `dependsOn`, `wait`, `healthCheckExprs`
- `references/fluxcd-helmrelease.md`: `chartRef`, CRD policies, post-renderers
- `references/linkerd.md`: HTTPRoute for east-west traffic
- `references/kubernetes.md`: NetworkPolicy for proxy-to-workload traffic
