---
title: Runtime Security
custom_edit_url: null
---

# Runtime Security Reference

Covers Falco — eBPF-based syscall monitoring for Kubernetes workloads. Falco is a CNCF project, open-source, and free to run. Complements supply chain security (pre-deployment controls) with in-cluster threat detection (post-deployment controls).

---

## Architecture

Falco runs as a DaemonSet on every node. It uses eBPF to hook into the Linux kernel and observe syscalls made by all containers on that node — without modifying the containers or the images.

```
Kernel syscalls (open, exec, connect, …)
  → Falco eBPF probe (per node)
  → Falco engine (rules evaluation)
  → Alert output
      ├── stdout (default)
      ├── Falcosidekick (fan-out: Slack, PagerDuty, SNS, webhook)
      └── gRPC output (for programmatic consumers)
```

### Driver options

| Driver | Requires | Use when |
|---|---|---|
| `modern_ebpf` | Linux 5.8+ kernel (BTF enabled) | EKS (AL2023), GKE (COS), recommended default |
| `ebpf` (classic) | Kernel headers on node | Older nodes without BTF support |
| `kmod` (kernel module) | Build toolchain + privileged | **Never use on managed K8s** — breaks on node OS upgrades |

**Always use eBPF on managed Kubernetes.** The kernel module requires privileged access and breaks whenever the node OS is upgraded (e.g., EKS AMI rotation, GKE node auto-upgrade).

---

## Installing Falco on EKS

```yaml
# falco-values.yaml — EKS with modern_ebpf driver
driver:
  kind: modern_ebpf   # no kernel headers required; needs Linux 5.8+ with BTF

falco:
  grpc:
    enabled: true     # enables gRPC output for programmatic consumers
  grpc_output:
    enabled: true
  json_output: true   # structured output; required for Falcosidekick parsing
  priority: warning   # suppress DEBUG and INFO from default ruleset

resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    memory: 512Mi     # cpu limit intentionally omitted — kernel event processing is bursty

tolerations:
  - effect: NoSchedule
    operator: Exists  # Falco must run on ALL nodes including tainted ones
  - effect: NoExecute
    operator: Exists
```

**Bottlerocket nodes:** set `driver.kind: modern_ebpf` — Bottlerocket does not ship kernel headers.

**Fargate:** Falco cannot run on Fargate. Fargate does not expose the node kernel to DaemonSets.

---

## Installing Falco on GKE

GKE Container-Optimized OS (COS) requires `modern_ebpf` (BTF enabled by default). Standard Ubuntu nodes can use either driver.

```yaml
driver:
  kind: modern_ebpf

tolerations:
  - effect: NoSchedule
    key: node.kubernetes.io/not-ready
    operator: Exists
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
    operator: Exists
```

**GKE Autopilot:** DaemonSets are not schedulable on Autopilot — Falco is not supported.

---

## Built-in Ruleset

The default Falco ruleset (`/etc/falco/falco_rules.yaml`) ships ~200 rules. Key ones to enable in production:

| Rule | Priority | What it detects |
|---|---|---|
| `Terminal shell in container` | NOTICE | Interactive shell spawned inside a running container |
| `Privilege Escalation via Sudo` | WARNING | `sudo` or `su` executed in a container |
| `Write below etc` | ERROR | Write to `/etc` inside a container |
| `Contact K8S API Server From Container` | NOTICE | Container calling the K8s API directly |
| `Unexpected outbound connection destination` | NOTICE | Outbound connection to unexpected IP/port |
| `Launch Privileged Container` | WARNING | Container started with `--privileged` |

Tune noise by adding process names or image repositories to built-in allow-list macros rather than disabling rules entirely.

---

## Writing Custom Rules

### Rule structure

```yaml
- rule: Unexpected binary executed in web container
  desc: A binary not in the known-good set was exec'd in the web-tier container
  condition: >
    spawned_process
    and container
    and container.image.repository = "ghcr.io/<org>/web"
    and not proc.name in (node, npm, sh, bash)
  output: >
    Unexpected binary in web container
    (user=%user.name image=%container.image.repository
     binary=%proc.name parent=%proc.pname cmdline=%proc.cmdline
     pod=%k8s.pod.name ns=%k8s.ns.name)
  priority: WARNING
  tags: [container, execution, custom]
```

### Key condition fields

| Field | Type | Example |
|---|---|---|
| `spawned_process` | macro | new process was exec'd |
| `container` | macro | event is inside a container |
| `proc.name` | string | `node`, `bash` |
| `proc.cmdline` | string | full command including args |
| `container.image.repository` | string | `ghcr.io/org/image` |
| `user.name` | string | unix username |
| `fd.net` | macro | event involves a network fd |
| `evt.type` | string | `execve`, `open`, `connect` |

### Lists and macros

```yaml
- list: allowed_web_binaries
  items: [node, npm, sh]

- macro: web_container
  condition: container.image.repository = "ghcr.io/<org>/web"

- rule: Unexpected binary in web container
  condition: spawned_process and web_container and not proc.name in (allowed_web_binaries)
  output: >
    Unexpected binary in web container
    (user=%user.name binary=%proc.name cmdline=%proc.cmdline pod=%k8s.pod.name)
  priority: WARNING
  tags: [container, execution, custom]
```

### Loading custom rules via Helm

```yaml
customRules:
  custom-rules.yaml: |-
    - list: allowed_web_binaries
      items: [node, npm, sh]
    - rule: Unexpected binary in web container
      condition: spawned_process and container and not proc.name in (allowed_web_binaries)
      output: "Binary %proc.name in container %container.name"
      priority: WARNING
```

### Testing rules

```bash
# Deploy the official event-generator to trigger known-bad syscall patterns
kubectl run event-generator \
  --image=falcosecurity/event-generator \
  --restart=Never \
  --rm -it -- run syscall

# Watch Falco logs on the same node
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep WARNING
```

---

## Falcosidekick: Alert Routing

Falcosidekick fans out Falco alerts to 50+ outputs. Enable alongside Falco:

```bash
helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true \
  -f falco-values.yaml
```

### Slack configuration

```yaml
falcosidekick:
  config:
    slack:
      webhookurl: "https://hooks.slack.com/services/<token>"
      minimumpriority: warning   # suppress DEBUG and INFO
      messageformat: >
        :rotating_light: *{{ .Rule }}* ({{ .Priority }})
        Container: `{{ index .OutputFields "container.name" }}`
        Image: `{{ index .OutputFields "container.image.repository" }}`
        Cmdline: `{{ index .OutputFields "proc.cmdline" }}`
        Pod: `{{ index .OutputFields "k8s.pod.name" }}` in `{{ index .OutputFields "k8s.ns.name" }}`
```

### Output types (selection)

| Output | Config key | Use case |
|---|---|---|
| Slack | `slack.webhookurl` | Team alert channel |
| Webhook | `webhook.address` | Custom handler or SIEM |
| AWS SNS | `aws.sns.topicarn` | AWS-native alert pipeline |
| PagerDuty | `pagerduty.routingkey` | On-call escalation |

---

## Bridging Falco → Kyverno

Falco detects threats at runtime. Kyverno can prevent re-admission of flagged workloads.

### Pattern

1. Falco alert fires (e.g., shell in container)
2. Alert webhook handler labels the Deployment: `security.platform/falco-alert: critical`
3. Kyverno `ValidatingPolicy` blocks `CREATE`/`UPDATE` on Deployments with that label
4. Ops team reviews, remediates, removes the label

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: block-falco-flagged-workloads
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments"]
  validations:
  - expression: >
      !has(object.metadata.labels) ||
      !('security.platform/falco-alert' in object.metadata.labels) ||
      object.metadata.labels['security.platform/falco-alert'] != 'critical'
    message: >
      This Deployment is flagged by a Falco critical alert. Remediate and remove
      the security.platform/falco-alert label before redeploying.
```

See `examples/runtime-security/falco-kyverno-bridge.yaml` for the full policy with annotations.

---

## Resource Sizing

| Component | CPU request | Memory request | Memory limit |
|---|---|---|---|
| Falco DaemonSet | 100m | 256Mi | 512Mi |
| Falcosidekick Deployment | 100m | 128Mi | 256Mi |
| Falcosidekick UI Deployment | 50m | 64Mi | 128Mi |

**Do not set CPU limits on Falco.** Kernel event processing is bursty; a CPU limit causes throttling and missed events.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Rule not firing | Wrong condition field or event type | Test with `falco-event-generator`; check Falco startup logs for rule load errors |
| Rule loaded but no alert | Event not reaching rule condition | Run event-generator; check `falco.priority` threshold |
| High CPU on Falco pod | Too many low-priority events | Add conditions to narrow scope; raise `falco.priority` to `warning` |
| Missed events | CPU throttling | Remove `limits.cpu` from Falco DaemonSet |
| Falcosidekick not receiving | Falco gRPC not enabled | Set `falco.grpc.enabled: true` and `falco.grpc_output.enabled: true` |
| DaemonSet not on tainted node | Missing toleration | Add `tolerations: [{effect: NoSchedule, operator: Exists}]` |
| No events on GKE | Wrong driver for COS | Set `driver.kind: modern_ebpf` |
| `failed to load module` | Using kmod driver on managed K8s | Switch to `driver.kind: modern_ebpf` |
| Custom rules not loaded | Wrong mount path | Rules load from `/etc/falco/rules.d/`, not `/etc/falco/` |
