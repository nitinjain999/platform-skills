---
title: "Flux CD: MCP"
custom_edit_url: null
---

# FluxCD MCP Server Reference

The Flux Operator MCP server (`flux-operator-mcp`) exposes live cluster state to AI assistants via the Model Context Protocol. It enables AI-assisted GitOps debugging without leaving the conversation.

---

## Installation

```bash
# Homebrew (macOS / Linux)
brew install controlplaneio-fluxcd/tap/flux-operator-mcp

# Binary (AMD64 / ARM64)
# Download from: https://github.com/controlplaneio-fluxcd/flux-operator-mcp/releases
```

---

## Configuration

Add to your MCP client config (Claude Code, Cursor, etc.):

```json
{
  "mcpServers": {
    "flux-operator-mcp": {
      "command": "flux-operator-mcp",
      "args": ["serve"],
      "env": {
        "KUBECONFIG": "/Users/username/.kube/config"
      }
    }
  }
}
```

> Use absolute paths — environment variables like `~` and `$HOME` do not expand in JSON config.

For production clusters, add `"--read-only"` to `args` to prevent the AI from modifying cluster state.

---

## Core workflows

### Cluster inspection

```
1. get_kubernetes_api_versions        → always call first; never assume apiVersion
2. get_flux_instance                  → FluxInstance status, Flux version, component health
3. list_flux_kustomizations           → overview of reconciliation state
4. list_flux_helm_releases            → HelmRelease status
```

After switching cluster contexts, run `get_flux_instance` before anything else.

### Troubleshoot a HelmRelease

```
1. get_flux_instance                  → confirm controllers healthy
2. get_flux_helm_release <name>       → spec, status, conditions
3. get_kubernetes_resource            → chart source (OCIRepository or HelmRepository)
4. get_kubernetes_resource            → valuesFrom ConfigMaps/Secrets
5. list_kubernetes_resources pods     → managed workload status
6. get_kubernetes_logs                → pod logs for runtime errors
```

### Troubleshoot a Kustomization

```
1. get_flux_instance                  → confirm kustomize-controller healthy
2. get_flux_kustomization <name>      → spec, status, conditions, inventory
3. get_kubernetes_resource            → source (GitRepository / OCIRepository)
4. get_kubernetes_resource            → substituteFrom ConfigMaps/Secrets
5. list_kubernetes_resources          → managed resources
6. get_kubernetes_logs                → pod logs
```

### Troubleshoot a ResourceSet

```
1. get_flux_instance                  → confirm flux-operator healthy
2. get_kubernetes_resource resourceset → status, inputsFrom, dependsOn
3. get_kubernetes_resource resourcesetinputprovider → provider status, exported values
4. list_kubernetes_resources          → generated Kustomizations/HelmReleases
```

### Multi-cluster comparison

```
1. list_kubernetes_contexts           → available clusters
2. For each context:
   get_flux_instance                  → version, components
   list_flux_kustomizations           → desired state
3. Compare specs across clusters      → identify drift
```

### Force reconciliation

```
# Reconcile source first, then the applier
flux reconcile source oci fleet-manifests -n flux-system
flux reconcile kustomization apps -n flux-system

# Or with --with-source flag (does both in one step)
flux reconcile kustomization apps --with-source -n flux-system
```

---

## Log analysis steps

1. Retrieve the Deployment and extract `matchLabels` and container name
2. List matching pods via label selector
3. Call `get_kubernetes_logs` with pod and container name
4. Look for: errors, warnings, `context deadline exceeded`, `artifact not found`, and recurring patterns

---

## Applying manifests

1. Verify field names from `get_kubernetes_api_versions`
2. Generate YAML using the verified schema
3. Call `apply_kubernetes_manifest`

If the resource is Flux-managed, the `overwrite: true` flag is required — but warn the user:

> Flux will revert changes on next reconciliation unless you also update the source.

---

## Key guidelines

- **Always call `get_kubernetes_api_versions` first** — never assume a resource's `apiVersion`
- **Secret values are masked** — the MCP server returns only `data` keys with empty values; never expose secret content
- **Avoid manually modifying Flux-managed resources** unless explicitly asked — Flux reverts them
- **After switching clusters**, run `get_flux_instance` before proceeding — cluster state differs

---

## Workflow summary table

| Task | Starting point |
|---|---|
| General cluster health | `get_flux_instance` → list Kustomizations → check HelmReleases |
| HelmRelease not reconciling | Controller status → resource spec → source → `valuesFrom` → pod logs |
| Kustomization stuck | Controller status → resource spec → source → `substituteFrom` → inventory |
| ResourceSet not generating | Operator status → ResourceSet spec → InputProvider → generated objects |
| Force sync | Reconcile source first, then applier (or `--with-source`) |
| Drift across clusters | Iterate contexts → collect specs → compare desired state |
