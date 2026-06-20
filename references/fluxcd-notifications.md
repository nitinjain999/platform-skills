---
title: "Flux CD: Notifications"
custom_edit_url: null
---

# FluxCD Notifications Reference

The notification-controller manages outgoing alerts (Provider + Alert) and incoming webhooks (Receiver). All resources share the namespace of their notification target.

---

## Provider

Defines an external service that receives routed events.

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack-platform
  namespace: flux-system
spec:
  type: slack
  channel: "#platform-alerts"
  secretRef:
    name: slack-webhook-url   # key: address (webhook URL)
```

**Provider categories:**

| Category | Types |
|---|---|
| Messaging | `slack`, `discord`, `msteams`, `telegram`, `matrix`, `googlechat`, `lark`, `webex` |
| Alerting / Monitoring | `alertmanager`, `grafana`, `sentry`, `pagerduty`, `opsgenie`, `datadog` |
| Event Streaming | `googlepubsub`, `azureeventhub`, `nats` |
| Git commit status | `github`, `gitlab`, `gitea`, `bitbucket`, `bitbucketserver`, `azuredevops` |
| Generic webhook | `generic` (plain JSON POST), `generic-hmac` (HMAC-signed POST) |

**Key spec fields:**

| Field | Purpose |
|---|---|
| `type` | Provider type (required) |
| `address` | Webhook URL (or inline in secretRef) |
| `channel` | Target channel (Slack, Discord, etc.) |
| `username` | Display name for bot messages |
| `secretRef.name` | Secret containing `address` key |
| `certSecretRef.name` | CA bundle for self-signed HTTPS endpoints |
| `suspend` | Pause alert delivery |

---

## Alert

Routes Flux events to a Provider with filtering.

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: platform-errors
  namespace: flux-system
spec:
  providerRef:
    name: slack-platform
  eventSeverity: error          # info | error
  eventSources:
    - kind: GitRepository
      name: "*"                  # wildcard — all resources of this kind
    - kind: Kustomization
      name: apps
      namespace: flux-system
    - kind: HelmRelease
      matchLabels:
        team: platform
  exclusionList:
    - ".*is already up to date.*"
  eventMetadata:
    cluster: production
    env: prod
```

**Severity levels:**

| Value | Delivers |
|---|---|
| `info` | All events (reconciliation start, success, failure) |
| `error` | Errors only — recommended for paging channels |

**Filtering:**

- `inclusionList` — regex patterns; only matching events pass
- `exclusionList` — regex patterns; exclusion takes precedence over inclusion
- `eventSources` supports: specific name, `"*"` wildcard, cross-namespace refs, `matchLabels` selector

**Valid source kinds:** `GitRepository`, `OCIRepository`, `HelmRepository`, `HelmChart`, `Bucket`, `Kustomization`, `HelmRelease`, `ImageRepository`, `ImagePolicy`, `ImageUpdateAutomation`, `FluxInstance`, `ResourceSet`

---

## Receiver

Accepts inbound webhooks and triggers immediate reconciliation by annotating resources with `reconcile.fluxcd.io/requestedAt`.

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: github-push
  namespace: flux-system
spec:
  type: github
  events:
    - "push"
  secretRef:
    name: github-webhook-token   # key: token (HMAC secret)
  resources:
    - kind: GitRepository
      name: fleet-manifests
      namespace: flux-system
```

After creation, the unique webhook path appears in `.status.webhookPath`. The full endpoint is:

```
https://<notification-controller-address><.status.webhookPath>
```

**Supported types:** `github`, `gitlab`, `gitea`, `bitbucket`, `azuredevops`, `generic`, `generic-hmac`

**CEL filtering** via `resourceFilter` allows expression-based matching — e.g., only trigger when the pushed tag matches the resource name:

```yaml
spec:
  resourceFilter: "resource.metadata.name == headers['X-GitHub-Event']"
```

---

## Common patterns

### Slack error alerting

```yaml
# Secret: slack-webhook-url with key "address"
---
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: "#gitops-alerts"
  secretRef:
    name: slack-webhook-url
---
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: cluster-errors
  namespace: flux-system
spec:
  providerRef:
    name: slack
  eventSeverity: error
  eventSources:
    - kind: Kustomization
      name: "*"
    - kind: HelmRelease
      name: "*"
```

### GitHub commit status on PRs

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: github-status
  namespace: flux-system
spec:
  type: github
  address: https://github.com/my-org/fleet-manifests
  secretRef:
    name: github-token   # key: token (PAT with repo:status scope)
---
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: staging-commit-status
  namespace: flux-system
spec:
  providerRef:
    name: github-status
  eventSeverity: info
  eventSources:
    - kind: Kustomization
      name: staging-apps
      namespace: flux-system
```

### Datadog event forwarding

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: datadog
  namespace: flux-system
spec:
  type: datadog
  address: https://api.datadoghq.eu/api/v1/events
  secretRef:
    name: datadog-api-key   # key: token (DD API key)
```

### Immediate Git sync on push (Receiver)

```yaml
# GitHub sends a push webhook → Receiver annotates GitRepository → source-controller fetches immediately
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: fleet-push
  namespace: flux-system
spec:
  type: github
  events:
    - "push"
  secretRef:
    name: github-webhook-secret
  resources:
    - kind: GitRepository
      name: fleet-manifests
      namespace: flux-system
```

---

## Validation

```bash
# List providers, alerts, receivers
flux get alert-providers -n flux-system
flux get alerts -n flux-system
flux get receivers -n flux-system

# Check receiver webhook path
kubectl get receiver github-push -n flux-system -o jsonpath='{.status.webhookPath}'

# Check alert delivery
kubectl describe alert cluster-errors -n flux-system
kubectl logs -n flux-system deploy/notification-controller | grep -i "error\|alert\|provider"
```
