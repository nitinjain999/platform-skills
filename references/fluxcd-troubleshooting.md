---
title: "Flux CD: Troubleshooting"
custom_edit_url: null
---

# FluxCD Troubleshooting — Failure Pattern Quick Reference

<!-- Adapted from https://github.com/fluxcd/agent-skills (Apache-2.0, The Flux authors)
     Sources: skills/gitops-cluster-debug/references/troubleshooting.md
              skills/gitops-knowledge/references/best-practices.md -->

Scannable incident cheat-sheet. Symptom → most likely cause → exact fix.
For the full 5-workflow debug procedure, use `/platform-skills:gitops debug`.

---

## Controller failures

| Symptom | Cause | Fix |
|---|---|---|
| Controller pod not running | Resource pressure, image pull failure, CRDs not installed | `kubectl describe pod -n flux-system`; check node conditions and image pull secrets |
| Controller `OOMKilled` / crashlooping | Memory limit too low | Raise limits via `FluxInstance spec.kustomize.patches`; delete pod to trigger immediate reschedule |
| `spec.suspend: true` on FluxInstance | Intentional pause — not an error | Confirm intent; resume: `kubectl patch fluxinstance flux --type=merge -p '{"spec":{"suspend":false}}'` |
| `Ready: Unknown` / Progressing | Reconciliation in flight | Wait; check `lastTransitionTime` vs `interval`; if older than 2× interval, check controller logs for backpressure |
| CRDs missing after upgrade | Flux component not upgraded | Re-run bootstrap or bump `FluxInstance.spec.distribution.version` |
| `flux-system` namespace empty | Flux never installed | Run `flux install` or deploy FluxInstance via Flux Operator |

---

## Source failures

### GitRepository

| Symptom | Cause | Fix |
|---|---|---|
| `FetchFailed: authentication required` | Missing or expired SSH key / PAT | Verify `spec.secretRef`; check `identity` + `known_hosts` keys in the Secret |
| `FetchFailed: repository not found` | Wrong URL or repo is private | Check `spec.url`; verify credentials have read access |
| `FetchFailed: reference not found` | Branch / tag does not exist | Check `spec.ref.branch` or `spec.ref.tag`; ensure it exists in Git |
| TLS error | Self-signed cert or wrong CA | Set `spec.secretRef` with `caFile` key, or `spec.insecure: true` (non-production only) |
| SSH URL rejected | SCP-style URL (`git@host:repo`) not supported | Change to `ssh://git@host/org/repo` |
| Stale `lastFetchedAt` | Controller backpressure or queue depth | Check `kubectl logs -n flux-system deploy/source-controller` for queue metrics |
| `sparseCheckout` slow / timeout | Large repo with narrow checkout — race on first clone | Increase `spec.timeout`; use `spec.ignore` patterns to reduce fetched content |

### OCIRepository

| Symptom | Cause | Fix |
|---|---|---|
| `FetchFailed: unauthorized` | Cloud registry auth not configured | Set `spec.provider: aws/gcp/azure`; verify workload identity annotation on source-controller SA |
| Cosign verification failed | Signature missing or OIDC issuer/subject mismatch | Check `spec.verify.matchOIDCIdentity`; verify CI pushed a signature after the image push step |
| `FetchFailed: layer not found` | `layerSelector.mediaType` missing or wrong | Set `layerSelector.mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip` for Helm charts |
| OCI `HelmRepository` shows no status | OCI type HelmRepository does not report conditions | Migrate to `OCIRepository` + `spec.chartRef` on the HelmRelease |

### HelmChart / HelmRepository

| Symptom | Cause | Fix |
|---|---|---|
| `HelmChart` not ready | Source `HelmRepository` not ready | Fix the HelmRepository first — HelmChart inherits its source's failure |
| `chart not found in repository` | Wrong chart name or version constraint | Verify `spec.chart` name and `spec.version` semver range against what the repo publishes |
| `version constraint yields no candidates` | Semver range too narrow or chart not yet published | Widen the range or pin a specific version that exists |

---

## Kustomization failures

| Symptom | Cause | Fix |
|---|---|---|
| `kustomize build failed` | Missing resource, invalid patch, or wrong `path` | Run `kustomize build ./path` locally to reproduce; check relative paths in `kustomization.yaml` |
| `BuildFailed: accumulating resources` | `resources:` reference points to a file that doesn't exist | Verify filenames and paths; check for case sensitivity issues |
| Variable not substituted (`${VAR}` left as literal) | `substituteFrom` ConfigMap/Secret missing `reconcile.fluxcd.io/watch: Enabled`, wrong key name, or `substituteFrom` on the wrong Kustomization | Add watch label; verify key names; ensure `substituteFrom` is on the Kustomization that **owns** the manifest — not a sibling |
| `health check timeout` | `dependsOn` resource not ready, or workload stuck in rollout | Inspect `dependsOn` chain; check the dependent resource's own status |
| Orphaned resources remain after file deletion | `spec.prune: false` | Set `spec.prune: true` unless orphan retention is intentional |
| `pruning disabled` alert | Same — `prune: false` | Same fix |
| Immutable field conflict (`field is immutable`) | Trying to patch a field Kubernetes won't allow changing in place | Set `spec.force: true` temporarily to recreate the resource; remove it after the conflict is resolved |
| `Variable substitution error: missing ConfigMap/Secret` | `substituteFrom` references an object that doesn't exist | Create the missing ConfigMap/Secret in the Kustomization's own namespace |
| RBAC: `forbidden` on apply | Controller SA lacks permission to manage the target resource | Add a RoleBinding/ClusterRoleBinding for the `kustomize-controller` SA or the Kustomization's `serviceAccountName` |

---

## HelmRelease failures

| Symptom | Cause | Fix |
|---|---|---|
| `rendered manifests contain a resource that already exists` / `cannot be imported into the current release: invalid ownership metadata` | **Ownership conflict** — a resource exists in the cluster that Helm did not create (or was created by a different release). Layer: **chart rendering**. Evidence: (1) extract the conflicting resource name from the error message — it is often different from the HelmRelease name; (2) `kubectl get <kind> <resource-name> -o yaml \| grep "meta.helm.sh"` — read the `meta.helm.sh/release-name` and `meta.helm.sh/release-namespace` annotations to identify the owning release; (3) `helm list -A` to find the owning release across all namespaces; (4) `flux logs --kind=HelmRelease --name=<name> -n <ns>` for full error context. Root cause: Helm cannot adopt a resource it did not create. Fix — choose one: (a) most common — `helm uninstall <owning-release> -n <owning-ns>` then `flux reconcile helmrelease <name> -n <ns>`; (b) if the resource is unowned/orphaned: `kubectl delete <kind> <resource-name>` then reconcile; (c) to adopt without deleting: add `meta.helm.sh/release-name: <release>` and `meta.helm.sh/release-namespace: <ns>` annotations plus `app.kubernetes.io/managed-by: Helm` label to the resource, then reconcile. Blast radius: `helm uninstall` deletes all Helm-managed resources including CRDs — for cert-manager this causes a brief certificate issuance lapse; confirm ownership before choosing option (a). Validation: `flux get helmrelease <name> -n <ns>` shows `Ready=True`; `kubectl get pods -n <ns>` shows all pods Running. |
| `install retries exhausted` | Hook timeout, resource conflict, pre/post-install hook failed | Check `helm-controller` logs; validate values against chart schema; inspect hook job/pod logs |
| `upgrade retries exhausted` | Same root causes but on upgrade path | Suspend, manually `helm rollback`, fix values, then resume |
| `Remediation exhausted` | Max retries reached — Flux stops retrying | Switch to `install.strategy.name: RetryOnFailure`; suspend + manually fix the Helm release state |
| Legacy vs modern remediation mismatch | Both `install.remediation.retries` and `install.strategy.name` set | Use modern only: `install.strategy.name: RetryOnFailure` and `upgrade.strategy.name: RetryOnFailure` |
| `chart not found` | OCIRepository missing `layerSelector.mediaType` | Add `layerSelector.mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip` |
| `valuesFrom` key missing | ConfigMap/Secret key name doesn't match what HelmRelease expects | Verify `valuesKey` in `valuesFrom[].valuesKey`; check the actual key in the ConfigMap |
| `valuesFrom` ConfigMap not watched | ConfigMap updated but HelmRelease not re-reconciled | Add `reconcile.fluxcd.io/watch: Enabled` label to the ConfigMap |
| `spec.chart.spec` and `spec.chartRef` both set | Mutually exclusive fields | Remove `spec.chart.spec`; use only `spec.chartRef` for OCI sources |
| Drift detected but no correction | `spec.driftDetection.mode: warn` — detects but doesn't fix | Change to `mode: enabled` to allow Flux to correct drift |
| HelmRelease stuck after `spec.force: true` | Force recreates but hooks fail on the recreated resource | Disable `force` after the immutable field conflict is resolved; check hook pod logs |
| Release in `failed` state, Flux not retrying | Remediation exhausted — Flux gives up | `flux suspend helmrelease <name> -n <ns>`; `helm rollback <name> -n <ns>`; fix; `flux resume` |
| Namespace created but never pruned | `targetNamespace` + `createNamespace: true` on HelmRelease — namespace created outside GitOps lifecycle | Remove `targetNamespace`/`createNamespace` from HelmRelease; create the namespace in the parent Kustomization or ResourceSet instead |

---

## ResourceSet failures

| Symptom | Cause | Fix |
|---|---|---|
| No resources generated | ResourceSetInputProvider not ready or returning empty inputs | Check provider status: `kubectl describe resourcesetinputprovider <name> -n flux-system` |
| Template rendering broken | Wrong delimiter — using `{{ }}` instead of `<< >>` | Change all template expressions to `<< inputs.field >>` format |
| Generated Kustomization/HelmRelease fails | Problem in the generated resource, not the ResourceSet itself | Drill into the generated resource with Workflow 2 or 3 |
| `dependsOn` not satisfied | ResourceSet depends on a Kustomization/HelmRelease that is not ready | Check the named dependency's status; `dependsOn` can reference any kind, not just Flux resources |
| `inputsFrom` provider returns stale data | Provider polling interval too long | Reduce `spec.interval` on the ResourceSetInputProvider |

---

## Finding the managing object (label-based tracing)

Every resource created by Flux carries labels identifying its parent. Use these to trace the full ownership chain without guessing.

```bash
# Who manages this HelmRelease?
kubectl get helmrelease <name> -n <ns> -o jsonpath='{.metadata.labels}' | jq

# Key labels to look for:
#   kustomize.toolkit.fluxcd.io/name    → parent Kustomization
#   kustomize.toolkit.fluxcd.io/namespace
#   resourceset.fluxcd.io/name          → parent ResourceSet
#   resourceset.fluxcd.io/namespace

# Find all resources managed by a specific Kustomization:
kubectl get all -A -l kustomize.toolkit.fluxcd.io/name=<kustomization-name>

# Find all resources generated by a ResourceSet:
kubectl get kustomization,helmrelease -A \
  -l resourceset.fluxcd.io/name=<resourceset-name>
```

---

## General debugging checklist

Run in this order — each step narrows the failure layer:

1. `flux get all -A` — anything not `Ready: True`?
2. `kubectl get pods -n flux-system` — all controllers running?
3. `kubectl get fluxinstance flux -n flux-system -o yaml` — FluxInstance healthy? (Flux Operator only)
4. `kubectl get fluxreport flux -n flux-system -o yaml` — cluster-wide reconciliation summary
5. `flux get sources all -A` — source fetching cleanly?
6. Check `spec.dependsOn` — is a dependency blocking?
7. Find the managing object via labels (see above)
8. Check controller SA RBAC: `kubectl auth can-i --list --as=system:serviceaccount:flux-system:kustomize-controller`
9. Check pod logs for the affected workload: `kubectl logs -n <ns> deploy/<name> --tail=100`
10. Check node pressure: `kubectl describe nodes | grep -A5 Conditions`
