---
name: openshift
description: OpenShift SCC diagnosis and hardening, Route TLS patterns, OpenShift GitOps app delivery, and cluster upgrade validation.
argument-hint: "[scc|route|gitops|upgrade|debug] [namespace or manifest path]"
title: "OpenShift Command"
sidebar_label: "openshift"
custom_edit_url: null
---

# OpenShift Command

Structured guidance for OpenShift SecurityContextConstraints, Routes, GitOps app delivery, and cluster upgrades.

## Activation

```
/platform-skills:openshift scc      # diagnose SCC rejections, grant minimum SCC, document exceptions
/platform-skills:openshift route    # Route TLS modes, troubleshoot 503/504, Route vs Ingress decision
/platform-skills:openshift gitops   # OpenShift GitOps (Argo CD) app delivery, sync waves, app-of-apps
/platform-skills:openshift upgrade  # pre-upgrade validation, operator impact, post-upgrade checks
/platform-skills:openshift debug    # structured debug — symptom → SCC | Route | Operator | Runtime
```

---

## Interactive Wizard (fires when no mode is provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. scc      — SCC rejection diagnosis, minimum SCC generation, Pod Security Admission interaction
  2. route    — Route TLS modes, 503/504 diagnosis, Route vs Ingress vs Gateway API decision
  3. gitops   — OpenShift GitOps (Argo CD), app-of-apps, sync waves, SCC + Argo interaction
  4. upgrade  — pre-upgrade checks, operator approval, post-upgrade validation, rollback
  5. debug    — general structured debug for any OpenShift symptom

Enter 1–5 or mode name:
```

**Q2 — Context** (after mode selected):
- **scc**: `Paste the rejection message or describe what the workload needs (privileged port, host path, fixed UID).`
- **route**: `Paste the Route YAML and describe the symptom (503, cert error, timeout, no traffic).`
- **gitops**: `New app delivery setup or debugging an existing Application? Which namespace?`
- **upgrade**: `Current OCP version and target version. Are you upgrading control plane, nodes, or operators?`
- **debug**: `Describe the symptom and paste any relevant events, logs, or error messages.`

---

## Mode: scc

**Triggers:** SCC, SecurityContextConstraints, forbidden, unable to validate, runAsUser, privileged, capability, hostPath

Read `references/openshift.md` → SecurityContextConstraints section before responding.

### Step 1 — Diagnose which SCC is blocking

```bash
# What SCC is currently assigned to a running pod
oc get pod <pod-name> -n <namespace> \
  -o jsonpath='{.metadata.annotations.openshift\.io/scc}'

# Simulate which SCC a service account would get for a given manifest
oc adm policy scc-subject-review -z <service-account> -n <namespace> \
  -f <manifest.yaml>

# Which SCCs the service account can use
oc adm policy who-can use scc restricted-v2 -n <namespace>
```

### Step 2 — Map rejection message to root cause

| Rejection message | Root cause | Fix |
|---|---|---|
| `unable to validate against any security context constraint` | No SCC grants the requested privilege | Grant a custom SCC with only what is needed |
| `runAsUser` rejected | Fixed UID outside the namespace UID range | Remove `runAsUser`, let OpenShift assign; or use `anyuid` (document exception) |
| `privileged` capability denied | Container requests `CAP_NET_ADMIN`, `CAP_SYS_PTRACE`, etc. | Remove the capability or create a custom SCC granting only that capability |
| `hostPath` volume denied | Pod mounts a host directory | Replace with `emptyDir` or PVC; if required, grant `hostmount-anyuid` to the SA |
| `allowPrivilegeEscalation` rejected | `securityContext.allowPrivilegeEscalation: true` | Set to `false` — this is enforced by `restricted-v2` |

### Step 3 — Grant minimum SCC

```yaml
# custom-scc.yaml — grant only what is needed
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: custom-net-admin
allowPrivilegedContainer: false
allowPrivilegeEscalation: false
runAsUser:
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
fsGroup:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
allowedCapabilities:
  - NET_ADMIN
volumes:
  - configMap
  - emptyDir
  - projected
  - secret
  - persistentVolumeClaim
```

```bash
oc apply -f custom-scc.yaml

oc adm policy add-scc-to-user custom-net-admin \
  -z <service-account> -n <namespace>

# Verify
oc adm policy who-can use scc custom-net-admin -n <namespace>
```

### SCC and Pod Security Admission (OCP 4.11+)

OpenShift 4.11+ runs both SCC and Kubernetes Pod Security Admission. PSA labels on the namespace add a second check — a pod blocked by PSA will not reach SCC evaluation.

```bash
# Check PSA labels on the namespace
oc get namespace <namespace> \
  -o jsonpath='{.metadata.labels}' | jq 'with_entries(select(.key | startswith("pod-security")))'
```

If PSA blocks what SCC permits, set the PSA label to match the granted SCC level or use `audit` mode while rolling out.

**Rollback:** Delete the `ClusterRoleBinding` or `RoleBinding` that grants the SCC. This revokes the SCC from the SA without affecting the SCC object itself.

---

## Mode: route

**Triggers:** Route, 503, 504, TLS, edge, passthrough, reencrypt, timeout, route not admitted, no traffic

Read `references/openshift.md` → Routes and ingress section before responding.

### TLS termination decision

| Scenario | Termination |
|---|---|
| Standard HTTPS, cert managed by router | `edge` |
| Pod handles its own TLS (mTLS, specific cert) | `passthrough` |
| End-to-end encryption with separate frontend and backend certs | `reencrypt` |
| WebSocket / gRPC | `passthrough` or `edge` + timeout annotation |

### Route templates

```yaml
# Edge — most common
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-app
  namespace: app-team
spec:
  host: my-app.apps.cluster.example.com
  to:
    kind: Service
    name: my-app
  port:
    targetPort: 8080
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

```yaml
# Passthrough — pod handles TLS
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-app-tls
  namespace: app-team
spec:
  host: my-app-tls.apps.cluster.example.com
  to:
    kind: Service
    name: my-app-tls
  port:
    targetPort: 8443
  tls:
    termination: passthrough
```

### Troubleshoot a failing Route

```bash
# Check route admission status
oc describe route <route-name> -n <namespace>

# Verify the service has ready endpoints
oc get endpoints <service-name> -n <namespace>

# Check router pod logs
oc logs -n openshift-ingress \
  -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
  --tail=100

# Test connectivity from inside the cluster
oc run curl-test --image=curlimages/curl --restart=Never --rm -it -- \
  curl -v http://<service-name>.<namespace>.svc.cluster.local:<port>
```

| Symptom | Cause | Fix |
|---|---|---|
| `503 Service Unavailable` | No ready endpoints | `oc get endpoints <svc> -n <ns>` — check pod readiness |
| Route admitted, no traffic | `targetPort` name vs number mismatch | Match `spec.port.targetPort` to the container port exactly |
| TLS error at browser | Cert CN/SAN does not match route host | Verify cert covers `spec.host` |
| Route not admitted | Hostname collision | `oc get routes -A \| grep <hostname>` |
| `504 Gateway Timeout` | Backend slow | Add annotation: `haproxy.router.openshift.io/timeout: 120s` |

**Validation:**
```bash
curl -I https://<route-host>
# Expected: 200 OK with correct TLS cert
```

---

## Mode: gitops

**Triggers:** OpenShift GitOps, Argo CD, ApplicationSet, sync wave, app-of-apps, argocd, GitOps operator

Read `references/openshift.md` → GitOps and app delivery section before responding.

### Platform layout

- `openshift-gitops` namespace: cluster-scoped Argo CD, managed by the operator. Use for cluster config and add-ons.
- Namespace-scoped Argo CD instances: use for app teams to limit blast radius.

```bash
# Check operator and default instance status
oc get csv -n openshift-gitops-operator | grep gitops
oc get argocd openshift-gitops -n openshift-gitops

# List all Applications
oc get applications -n openshift-gitops

# Force sync
oc patch application <app-name> -n openshift-gitops \
  --type merge -p '{"operation":{"sync":{}}}'
```

### App-of-apps pattern

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-config
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/org/gitops-repo
    targetRevision: main
    path: cluster-config/apps
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Sync waves — ordering operators before workloads

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-10"   # operators first, then apps
```

Wave order convention:
- `-20`: namespaces, RBAC
- `-10`: operators (Subscription)
- `0`: operator-managed CRs (CRDs ready)
- `10`: application workloads

### SCC and Argo CD

`argocd-application-controller` needs SCC review permissions or resources bound to SCCs show as `Unknown` in sync status:

```bash
oc adm policy add-cluster-role-to-user \
  system:openshift:scc-review \
  -z argocd-application-controller \
  -n openshift-gitops
```

**Handoff:** For deeper Argo CD debug and audit → `/platform-skills:gitops`

---

## Mode: upgrade

**Triggers:** upgrade, ClusterVersion, channel, version, operator update, InstallPlan, pre-upgrade, post-upgrade

Read `references/openshift.md` → Day-2 operations section before responding.

### Pre-upgrade checklist

```bash
# All cluster operators healthy
oc get clusteroperators | grep -v "True.*False.*False"

# All nodes ready
oc get nodes | grep -v Ready

# MachineConfigPool not degraded
oc get machineconfigpool

# Check for API removals — deprecated APIs in use
oc get apirequestcounts \
  | grep -v "0 " | sort -k3 -rn | head -20

# Operator subscriptions — identify Manual approval mode
oc get subscriptions -A \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CHANNEL:.spec.channel,APPROVAL:.spec.installPlanApproval'

# Pending InstallPlans waiting for manual approval
oc get installplan -A | grep Manual
```

### Initiate upgrade

```bash
# Check available versions on the current channel
oc get clusterversion version \
  -o jsonpath='{.status.availableUpdates[*].version}' | tr ' ' '\n'

# Switch to the next minor channel if needed
oc patch clusterversion version --type merge \
  -p '{"spec":{"channel":"stable-4.15"}}'

# Trigger the upgrade to a specific version
oc adm upgrade --to=4.15.3
```

### Approve pending operator InstallPlans

```bash
oc patch installplan <install-plan-name> -n <namespace> \
  --type merge -p '{"spec":{"approved":true}}'
```

### Post-upgrade validation

```bash
oc get clusteroperators
oc get nodes
oc get machineconfigpool

# Check for SCC policy regressions after upgrade
oc get events -A --field-selector reason=FailedCreate \
  | grep -i scc
```

### Rollback note

OpenShift cluster upgrades are not directly reversible once the control plane advances. Safe path:
1. Wait for all operators and node pools to be healthy before proceeding to node upgrades
2. Roll back individual operators via InstallPlan if one breaks
3. Fix SCC grants if policy tightened — do not revert the cluster version
4. For catastrophic failure: restore from etcd backup (taken before upgrade)

---

## Mode: debug

**Triggers:** failing, not starting, rejected, error, broken, debug, troubleshoot

Classify the symptom, then apply the matching framework:

```
1. Pod not starting        → SCC rejection or image pull error → mode: scc
2. Traffic not reaching app → Route misconfiguration → mode: route
3. Resource not syncing    → Argo CD / GitOps issue → mode: gitops
4. Cluster upgrade stuck   → Operator or MCP issue → mode: upgrade
5. Application runtime error → standard Kubernetes debug
```

For standard Kubernetes debug (crashloop, OOMKill, pending, image pull) → `/platform-skills:kubernetes debug`

For evidence collection:

```bash
# Events in the namespace — most failures surface here first
oc get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Pod state and describe
oc get pod <pod-name> -n <namespace>
oc describe pod <pod-name> -n <namespace>

# Logs — current and previous
oc logs <pod-name> -n <namespace>
oc logs <pod-name> -n <namespace> --previous
```

Always end a debug session with:
- **Validation command** — exact command that confirms the fix worked
- **Rollback** — how to safely undo the change if it makes things worse

---

## Common mistakes

- **Editing upstream manifests for vanilla Kubernetes and deploying to OpenShift** — `runAsRoot`, host paths, and privileged capabilities that work on vanilla clusters are rejected by `restricted-v2` SCC. Validate with `oc adm policy scc-subject-review` before deploying.
- **Using ClusterRoleBinding for app teams** — grants access cluster-wide. App teams need `RoleBinding` scoped to their namespace.
- **Skipping sync wave ordering** — applying application workloads before operators are ready causes reconciliation errors. Add sync wave annotations to control order.
- **Upgrading without checking `apirequestcounts`** — removed APIs in the target version will break existing workloads silently at upgrade. Always check before initiating.
- **Ignoring PSA labels after OCP 4.11** — SCCs and PSA both block pods. A pod that passes SCC can still be blocked by the namespace PSA label.

---

## Reference

Full guidance: `references/openshift.md`

For standard Kubernetes debug: `/platform-skills:kubernetes`

For Argo CD deep debug: `/platform-skills:gitops`

Examples:
- `examples/openshift/` — Route, SCC, and GitOps baseline patterns
