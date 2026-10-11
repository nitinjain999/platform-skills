---
name: gateway-api
description: Migrate from the retired ingress-nginx controller to Kubernetes Gateway API, and design, debug, and review Gateway API ingress. Covers annotation inventory and risk triage, ingress2gateway conversion, implementation choice (Envoy Gateway default, Cilium, Istio, NGINX Gateway Fabric, AWS Load Balancer Controller), CRD channel and lifecycle, shared-Gateway ownership, cert-manager listener TLS, Flux layering, parallel-run DNS cutover, and rollback. Use when asked to "migrate off ingress-nginx", "convert my Ingresses to HTTPRoute", "set up Gateway API", "why is my HTTPRoute not attached", or "plan the ingress cutover". Flux reconciliation stuck → /platform-skills:gitops. East-west HTTPRoute in a mesh → /platform-skills:linkerd.
argument-hint: "[assess|convert|scaffold|cutover|debug|review|rollback] [namespace, file, or description]"
title: "Gateway API Command"
sidebar_label: "gateway-api"
custom_edit_url: null
---

Move ingress traffic off the retired ingress-nginx controller onto Gateway API without a user-visible change, and keep a fast rollback until the old path is provably unused.

Read `references/gateway-api.md` before responding. It holds the implementation matrix, the ownership model, CRD channel rules, the ingress2gateway v1.2.0 annotation coverage table, cert-manager requirements, Flux layering, the seven-phase cutover, rollback by stage, and the troubleshooting table. The working layout is `examples/fluxcd/basic-monorepo`; a before/after pair for one Ingress is in `examples/gateway-api`.

**This command is interactive by default.** With no arguments, ask the three questions below, then run the matching mode. Never apply converted manifests or change DNS yourself: produce the change, the validation, and the rollback, and let the user run it.

## Questions (no arguments)

Ask one at a time:

1. **Where are you?** `assess` (have ingress-nginx, not started) / `convert` (ready to translate) / `scaffold` (new cluster, no Ingress yet) / `cutover` (Gateway works, traffic not moved) / `debug` (a route or Gateway is not working) / `review` (check existing Gateway API config) / `rollback`
2. **Which implementation?** Envoy Gateway (default) / Cilium / Istio / NGINX Gateway Fabric / AWS Load Balancer Controller / undecided. If undecided, apply the "Choosing an implementation" table: pick by what the team already operates
3. **How is the cluster delivered?** Flux / Argo CD / Helm or kubectl directly

## Mode dispatch

| Mode | What it does | Mutates anything? |
|---|---|---|
| `assess` | Inventories Ingresses, classes and annotations; classifies each annotation as auto, decision, or blocked | No |
| `convert` | Runs ingress2gateway, then rewrites output for the shared-Gateway model | Writes files only |
| `scaffold` | Generates CRDs, controller, GatewayClass, Gateway, cert-manager and Flux layers | Writes files only |
| `cutover` | Produces the per-hostname shadow test, DNS plan, soak criteria and decommission gate | No |
| `debug` | Diagnoses a route, listener, certificate or Gateway address problem | No |
| `review` | Reviews Gateway API manifests for correctness, security and operational safety | No |
| `rollback` | Picks the rollback for the stage reached | No |

---

## Mode: assess

1. Collect:
   ```bash
   kubectl get ingressclass
   # One row per Ingress annotation, keeping the resource identity and hosts,
   # so every annotation can be traced to the Ingress that carries it.
   # Columns: namespace, name, class, hosts, annotation, value. The value is
   # kept because several blockers are value-dependent (`rewrite-target: /$1`
   # uses a capture group; a snippet's body is what has to be redesigned).
   # @tsv escapes tabs and newlines, so a multi-line snippet stays on one row.
   # An Ingress with no nginx annotation still gets one row with "-".
   kubectl get ingress -A -o json | jq -r '
     .items[]
     | (.metadata.annotations // {}) as $a
     | [.metadata.namespace, .metadata.name,
        (.spec.ingressClassName // $a["kubernetes.io/ingress.class"] // "-"),
        ([.spec.rules[]?.host // "*"] | unique | join(","))] as $id
     | ([$a | to_entries[] | select(.key | startswith("nginx.ingress.kubernetes.io/")) | [.key, .value]]
        | if length == 0 then [["-", "-"]] else . end)[]
     | $id + . | @tsv' > ingress-inventory.tsv
   column -t -s $'\t' ingress-inventory.tsv
   # Cluster-wide count per annotation, to size the work
   kubectl get ingress -A -o json \
     | jq -r '.items[] | .metadata.annotations // {} | keys[]' \
     | grep '^nginx.ingress.kubernetes.io/' | sort | uniq -c | sort -rn
   # Controller-wide settings also change behaviour, not just annotations
   kubectl get configmap -A -l app.kubernetes.io/name=ingress-nginx -o yaml
   ```
2. Classify every annotation against the coverage table in `references/gateway-api.md`:
   - **auto**: ingress2gateway converts it to core Gateway API
   - **decision**: converted to an implementation-specific policy, or converted with different semantics (timeouts, IP ranges, regex)
   - **blocked**: warned-and-dropped or not recognised (`configuration-snippet`, `server-snippet`, auth, rate limiting). Each needs an owner and a design before conversion
3. Flag controller ConfigMap keys that set global behaviour (custom headers, timeouts, `use-forwarded-headers`, `ssl-redirect`). They do not appear on any Ingress and are the easiest to lose
4. Output a table: namespace, Ingress, host, class, annotations by category, owner, blocking yes/no. End with the count of blocked items. Do not proceed to `convert` while any item is blocked without an agreed decision

## Mode: convert

1. Confirm `assess` has no open blocked items
2. Run, one namespace at a time:
   ```bash
   ingress2gateway print --providers=ingress-nginx --emitter=envoy-gateway \
     -n <namespace> > converted-<namespace>.yaml
   ```
   Use `--emitter=standard` for a non-Envoy implementation, and `--ingress-nginx-ingress-class=<class>` when the class is not `nginx`. Never pass `--allow-experimental-gw-api` on a standard-channel cluster
3. Treat every warning as a finding. List each one with the Ingress it came from
4. Rewrite for the shared-Gateway model:
   - Delete generated `Gateway` objects
   - Set each route's `parentRefs` to `platform-gateway` in `envoy-gateway-system`, with the right `sectionName`
   - Move TLS to a Gateway HTTPS listener per hostname (cert-manager requirement)
   - Bind each HTTPS listener's `allowedRoutes` to the namespace that owns its hostname (`kubernetes.io/metadata.name`)
   - Use the Service **port number** in `backendRefs`
5. Re-express each `decision` item (filter or policy) and show it next to the original annotation
6. Validate:
   ```bash
   kubeconform -strict -summary \
     -schema-location default \
     -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
     converted-<namespace>.yaml
   ```
7. State what is not covered by the converted output, plainly

## Mode: scaffold

Generate the layout from `examples/fluxcd/basic-monorepo`, adapted to the answers:

1. **CRDs:** **standard** channel, applied as plain manifests, never through a Helm release (they exceed the 1 MiB release Secret). For Flux: one `Kustomization` per source with `prune: false` and `deletionPolicy: Orphan`: Gateway API `config/crd/standard` at the pinned tag, plus Envoy Gateway's `charts/crds/crds/generated/` from the pinned chart artifact. Set `crds.enabled: false` on the controller chart
2. **Controller:** pinned exact version; at least two control-plane replicas in production
3. **Data plane:** at least two proxy replicas plus a PodDisruptionBudget in production. Never a PDB of `minAvailable: 1` on one replica
4. **GatewayClass and Gateway:** one shared Gateway owned by the platform team. Port 80 `from: Same` (redirect and ACME only), HTTPS listeners `from: Selector` bound to the namespace that owns the hostname via `kubernetes.io/metadata.name`. Never `from: All`, and never one shared opt-in label across listeners: either lets a team claim another team's hostname. App namespaces are created in the platform layer, never by the app layer
5. **Redirect:** a platform-owned `RequestRedirect` route on port 80 with `statusCode: 308`
6. **TLS:** cert-manager v1.15+ with `config.gatewayAPI.enabled: true`, the `cert-manager.io/cluster-issuer` annotation on the Gateway, and the `gatewayHTTPRoute` HTTP-01 solver. cert-manager must start after the CRDs exist (its layer `dependsOn` the CRD Kustomizations)
7. **Delivery:** for Flux, three layers (`infrastructure` → `infrastructure-configs` → `apps`) with a `healthCheckExprs` entry on Gateway `Programmed`. For Argo CD, sync waves in the same order
8. **NetworkPolicy:** allow app ingress only from the proxy pods (namespace **and** pod selector)
9. Run `bash examples/gateway-api/gateway-api-validate.sh` against the adapted copy, or the kubeconform command above

## Mode: cutover

Produce a per-hostname plan following the migration path in `references/gateway-api.md`:

1. **Pre-flight:** Gateway `Programmed=True`, every route `Accepted=True` and `ResolvedRefs=True`, every certificate `Ready`
2. **TTL:** lower the DNS TTL to 60s at least one old-TTL period before the switch
3. **Shadow test** each hostname against the new address without touching DNS:
   ```bash
   # The address can be an IP or a hostname (cloud LBs often publish a DNS name).
   # --connect-to accepts either and keeps the URL host for Host and TLS SNI;
   # --resolve only accepts an IP and fails to parse a hostname.
   NEW_ADDR=$(kubectl get gateway platform-gateway -n envoy-gateway-system -o jsonpath='{.status.addresses[0].value}')
   curl -sS -o /dev/null -w '%{http_code} %{time_total}\n' \
     --connect-to <host>:443:"$NEW_ADDR":443 https://<host>/<health-path>
   ```
   Compare status codes, key response headers, redirects and p99 latency with the old path
4. **Order:** lowest-risk hostname first; one hostname per change
5. **Soak criteria:** error rate and p99 within SLO for at least one full business cycle
6. **Decommission gate:** no requests on the old load balancer for the whole soak. Decommissioning is its own change, never the cutover change

**Blast radius:** one hostname per DNS change. Nothing else moves.

## Mode: debug

1. Collect:
   ```bash
   kubectl get gatewayclass
   kubectl get gateway -A
   kubectl describe gateway <name> -n <namespace>
   kubectl get httproute <name> -n <namespace> -o yaml   # read .status.parents
   kubectl get certificate,certificaterequest -A
   kubectl get svc -n envoy-gateway-system
   kubectl logs -n envoy-gateway-system deploy/envoy-gateway --tail=100
   ```
2. Classify the layer: **CRD/chart rendering** (install fails, admission policy errors), **reconciliation** (Flux or Argo stuck, `no matches for kind`), **runtime** (route or Gateway conditions)
3. Read the condition `reason` and match it to the troubleshooting table in `references/gateway-api.md` (`NotAllowedByListeners`, `NoMatchingListenerHostname`, `BackendNotFound`, `RefNotPermitted`, `AddressNotAssigned`)
4. State the most likely root cause with the exact field to change, the corrected YAML, the verification command, and the rollback

## Mode: review

Review in this order and separate critical findings from improvements:

1. **Correctness:** `backendRefs` use port numbers; listener hostnames cover route hostnames; every HTTPS listener has `hostname`, `tls.mode: Terminate` and `certificateRefs`; configs depend on CRDs
2. **Security:** no `from: All` on shared listeners; each HTTPS listener binds to the namespace owning its hostname, not a shared label; `ReferenceGrant`s are as narrow as possible; NetworkPolicy admits only proxy pods; no experimental channel unless deliberate
3. **Operational safety:** CRDs are plain manifests that are never pruned or deleted with their owner; the controller chart does not install CRDs; proxy replicas ≥ 2 with a PDB in production; exact version pins; a `Programmed` health check
4. **Portability:** implementation-specific policies are listed and justified

## Mode: rollback

Ask which stage was reached, then apply the rollback table in `references/gateway-api.md`:

| Stage | Rollback |
|---|---|
| Before DNS cutover | Delete the new routes; nothing user-facing changed |
| After cutover, ingress-nginx still running | Point DNS back at the ingress-nginx address |
| After decommission | Revert the decommission commit; Flux or Argo re-creates ingress-nginx and the Ingress objects; then switch DNS |
| Bad CRD upgrade | Revert the CRD source tag in Git. Never delete a CRD or its Kustomization |

## Output format

Every mode ends with:

- **Findings or changes**, with exact files and fields
- **Blast radius**, in one line
- **Validation**, as commands to run
- **Rollback**, as the concrete step for the stage reached
