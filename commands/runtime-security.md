---
name: runtime-security
description: Detect and respond to in-container threats at the syscall level using Falco (eBPF-based, CNCF, open-source, no license cost). Covers Falco installation on EKS/GKE with eBPF driver, custom rule authoring, alert routing via Falcosidekick, rule debugging, and bridging Falco runtime signals to Kyverno admission enforcement. Use when asked to "detect privilege escalation in containers", "set up runtime threat detection", "write a Falco rule", "route Falco alerts to Slack", or "debug why my Falco rule is not firing".
argument-hint: "[install|rules|alerts|debug|harden] [description or symptom]"
---

Detect and respond to threats inside running containers using Falco.

## Mode: install

Deploy Falco on Kubernetes (EKS or GKE) using the eBPF driver via Helm.

Prerequisites:
- Helm 3.x
- `kubectl` access to the target cluster
- Node OS: Amazon Linux 2/2023 (EKS) or Container-Optimized OS (GKE) — both support eBPF

Steps:
1. Add the Falco Helm repository:
   ```bash
   helm repo add falcosecurity https://falcosecurity.github.io/charts
   helm repo update
   ```
2. Install Falco with eBPF driver (never kernel module on managed K8s):
   ```bash
   helm install falco falcosecurity/falco \
     --namespace falco \
     --create-namespace \
     -f examples/runtime-security/falco-values.yaml
   ```
3. Verify DaemonSet is running on all nodes:
   ```bash
   kubectl rollout status daemonset/falco -n falco
   kubectl get pods -n falco -o wide
   ```
4. Confirm Falco is receiving events:
   ```bash
   kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
   ```
   Expected: lines like `Notice A shell was spawned...` (from the default ruleset test events)

EKS-specific note: if using Bottlerocket nodes, set `driver.kind: modern_ebpf` in Helm values — Bottlerocket does not ship kernel headers for the classic eBPF probe.

GKE-specific note: COS nodes require `driver.kind: modern_ebpf`. GKE Autopilot does not support Falco (no DaemonSet scheduling).

Reference: `references/runtime-security.md` → eBPF driver, Node OS compatibility

## Mode: rules

Write and test custom Falco rules.

Steps:
1. Explain the rule structure:
   ```yaml
   - rule: Shell spawned in container
     desc: A shell was spawned inside a container — potential interactive intrusion
     condition: >
       spawned_process
       and container
       and shell_procs
       and not container.image.repository in (allowed_shell_images)
     output: >
       Shell spawned in container
       (user=%user.name user_id=%user.uid
        container=%container.name image=%container.image.repository
        shell=%proc.name parent=%proc.pname cmdline=%proc.cmdline)
     priority: WARNING
     tags: [container, shell, mitre_execution]
   ```
2. Key condition fields:
   - `spawned_process` — a new process was exec'd
   - `container` — event is inside a container (not on the host)
   - `proc.name` — process name
   - `container.image.repository` — image name without tag
   - `fd.net` — network file descriptor (for connection events)
3. Test with falco-event-generator:
   ```bash
   kubectl run event-generator \
     --image=falcosecurity/event-generator \
     --restart=Never \
     --rm -it -- run syscall
   ```
   Then check logs: `kubectl logs -n falco -l app.kubernetes.io/name=falco | grep WARNING`
4. Load custom rules via Helm values:
   ```yaml
   customRules:
     custom-rules.yaml: |-
       - rule: Shell spawned in container
         ...
   ```

Reference: `references/runtime-security.md` → Rule syntax, Condition fields, Lists and macros

## Mode: alerts

Configure Falcosidekick to route Falco alerts to Slack, webhooks, or other outputs.

Steps:
1. Install Falcosidekick alongside Falco:
   ```bash
   helm install falco falcosecurity/falco \
     --namespace falco \
     --create-namespace \
     --set falcosidekick.enabled=true \
     --set falcosidekick.webui.enabled=true \
     -f examples/runtime-security/falcosidekick-values.yaml
   ```
2. Configure Slack output in Falcosidekick values:
   ```yaml
   falcosidekick:
     config:
       slack:
         webhookurl: "https://hooks.slack.com/services/<token>"
         minimumpriority: warning
         messageformat: >
           Alert: *{{ .Rule }}* (Priority: {{ .Priority }})
           Container: `{{ index .OutputFields "container.name" }}`
           Image: `{{ index .OutputFields "container.image.repository" }}`
   ```
3. Verify alerts are routing:
   ```bash
   kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802
   # Open http://localhost:2802 — events appear in the UI
   ```
4. Deduplication: set `slack.minimumpriority: warning` to suppress DEBUG/INFO noise

Reference: `references/runtime-security.md` → Falcosidekick, Output types

## Mode: debug

Diagnose why a Falco rule is not firing.

Checklist (work through in order):
1. **Is Falco running?**
   ```bash
   kubectl get pods -n falco -o wide
   kubectl logs -n falco -l app.kubernetes.io/name=falco | tail -20
   ```
2. **Is the rule loaded?**
   ```bash
   kubectl exec -n falco daemonset/falco -- falco --list-rules | grep "<rule name>"
   ```
3. **Is the condition correct?** Test the event type:
   ```bash
   kubectl exec -n falco daemonset/falco -- falco --validate /etc/falco/custom-rules.yaml
   ```
4. **Is the event being generated?** Use event-generator for syscall rules:
   ```bash
   kubectl run test --image=falcosecurity/event-generator --rm -it -- run syscall
   ```
5. **Is the priority too low?** If `falcosidekick.config.slack.minimumpriority: error`, rules with `priority: WARNING` are silently dropped. Adjust priority or threshold.
6. **Is there a macro override?** Check if a built-in macro like `never_true` is shadowing your condition:
   ```bash
   kubectl exec -n falco daemonset/falco -- falco --list-macros | grep "<macro name>"
   ```

Reference: `references/runtime-security.md` → Troubleshooting

## Mode: harden

Map Falco runtime alerts to Kyverno admission policies to prevent redeployment of flagged workloads.

Steps:
1. Explain the bridge pattern: Falco detects a runtime violation → alert metadata is added as a label/annotation to the offending Pod or Deployment → Kyverno admission policy blocks future admission of workloads with that label
2. Label the offending workload (from an alert webhook handler or manual response):
   ```bash
   kubectl label deployment <name> -n <namespace> \
     security.platform/falco-alert=critical
   ```
3. Apply the Kyverno policy to block re-admission:
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
       message: "Deployment is flagged by a Falco critical alert and cannot be re-admitted. Remove the flag after remediation."
   ```
4. Remediation workflow: fix the workload → remove the label → re-admit

Reference: `references/runtime-security.md` → Kyverno bridge, `references/kyverno.md` → ValidatingPolicy
