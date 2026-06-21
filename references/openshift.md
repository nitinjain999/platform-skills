---
title: OpenShift
custom_edit_url: null
---

# OpenShift Reference

## Contents

- Scope
- Platform-specific constraints
- SecurityContextConstraints (SCC)
- Routes and ingress
- GitOps and app delivery
- Security and tenancy
- Day-2 operations — upgrades

## Scope

Use OpenShift guidance when the request involves:

- OpenShift-specific security context constraints
- Routes, operators, machine configs, or cluster version management
- Multi-tenant namespace/project patterns on Red Hat OpenShift
- Integrating platform add-ons with OpenShift defaults and guardrails

Start from standard Kubernetes patterns, then adapt to OpenShift-native controls rather than fighting them.

## Platform-specific constraints

- OpenShift commonly enforces restricted security defaults that will break manifests written for permissive vanilla Kubernetes clusters.
- Validate UID, FSGroup, capability, and privilege assumptions early.
- Prefer Operators for platform capabilities that OpenShift already manages well.
- Use `Route` when exposing workloads through OpenShift ingress patterns instead of forcing generic ingress designs everywhere.

---

## SecurityContextConstraints (SCC)

### How SCCs work

SCCs are OpenShift's admission control layer for pod security. Every pod is matched to an SCC at admission time. If no SCC permits the pod's requested privileges, the pod is rejected before scheduling.

Priority order when multiple SCCs match: higher `.priority` value wins. Service account, user, and group bindings all grant SCCs.

### SCC admission diagnostic

```bash
# What SCC was assigned to a running pod
oc get pod <pod-name> -n <namespace> \
  -o jsonpath='{.metadata.annotations.openshift\.io/scc}'

# List subjects (users, groups, SA) that are allowed to use a specific SCC
oc adm policy who-can use scc restricted-v2 -n <namespace>

# List Role/ClusterRole names bound to a specific service account
oc get rolebindings,clusterrolebindings -n <namespace> -o json \
  | jq -r '
    .items[]
    | select(
        .subjects[]?
        | select(.kind=="ServiceAccount"
            and .name=="<sa-name>"
            and .namespace=="<namespace>")
      )
    | .roleRef.name'

# Check SCC requirements vs pod spec
oc adm policy scc-subject-review -z <service-account> -n <namespace> \
  -f <pod-or-deployment.yaml>

# Check which SCC a pod would get without applying
oc adm policy scc-review -z <service-account> -n <namespace> \
  -f <pod-or-deployment.yaml>
```

### Common SCC rejection causes and fixes

| Rejection message | Root cause | Fix |
|---|---|---|
| `unable to validate against any security context constraint` | No SCC grants the requested UID, capability, or volume type | Add the specific permission to a custom SCC or grant a wider SCC to the SA |
| `runAsUser` rejected | Pod requests a fixed UID outside the namespace UID range | Remove `runAsUser` and let OpenShift assign from the namespace range, or use `anyuid` SCC (document exception) |
| `privileged` capability denied | Container requests `CAP_NET_ADMIN`, `CAP_SYS_PTRACE`, or similar | Remove the capability if not needed; if needed, create a custom SCC granting only that capability |
| `hostPath` volume denied | Pod mounts a host path | Replace with `emptyDir`, `PVC`, or `ConfigMap`; if genuinely needed (e.g. node agent), grant `hostmount-anyuid` SCC to the SA |
| `allowPrivilegeEscalation` rejected | `securityContext.allowPrivilegeEscalation: true` | Set to `false`; this is the default in `restricted-v2` |

### Granting a custom SCC (minimum privilege)

```yaml
# custom-scc.yaml — grant only what is needed; document why each privilege is required
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: custom-net-admin
allowPrivilegedContainer: false
allowPrivilegeEscalation: false
runAsUser:
  type: MustRunAsRange        # let namespace assign from its UID range
seLinuxContext:
  type: MustRunAs
fsGroup:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
allowedCapabilities:
  - NET_ADMIN                 # document: required for CNI plugin X
volumes:
  - configMap
  - emptyDir
  - projected
  - secret
  - persistentVolumeClaim
```

```bash
# Apply SCC
oc apply -f custom-scc.yaml

# Grant it to a service account
oc adm policy add-scc-to-user custom-net-admin \
  -z <service-account> -n <namespace>

# Verify
oc adm policy who-can use scc custom-net-admin -n <namespace>
```

### SCC and Kubernetes Pod Security Admission

OpenShift 4.11+ ships both SCCs and Kubernetes Pod Security Admission (PSA). SCCs remain the enforcing layer; PSA labels on namespaces add a secondary check. A pod can be blocked by either.

```bash
# Check namespace PSA labels
oc get namespace <namespace> \
  -o jsonpath='{.metadata.labels}' | jq

# Common label combination for OpenShift workloads
# pod-security.kubernetes.io/enforce: restricted
# pod-security.kubernetes.io/warn: restricted
```

If PSA and SCC conflict (PSA blocks what SCC permits), set the PSA label to match the granted SCC level or use `audit` mode first.

---

## Routes and ingress

### Route vs Ingress — decision matrix

| Scenario | Use |
|---|---|
| Standard HTTP/HTTPS on OpenShift | `Route` |
| Multi-cluster or cloud-neutral portability | `Ingress` (OpenShift creates Route behind it) |
| WebSocket or gRPC | `Route` with `haproxy.router.openshift.io/timeout` annotation |
| Custom cert per domain | `Route` with `spec.tls.certificate` / `spec.tls.key` |
| Wildcard subdomains | `Route` with `spec.wildcardPolicy: Subdomain` |
| Gateway API (OCP 4.14+) | `HTTPRoute` via OpenShift Gateway API operator |

### Route TLS termination modes

```yaml
# Edge — TLS terminates at the router; backend receives plain HTTP
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-app-edge
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

---
# Passthrough — TLS passes to the pod unchanged; pod handles TLS
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-app-passthrough
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

---
# Re-encrypt — TLS terminates at router, new TLS to backend; separate certs
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: my-app-reencrypt
  namespace: app-team
spec:
  host: my-app-secure.apps.cluster.example.com
  to:
    kind: Service
    name: my-app
  port:
    targetPort: 8443
  tls:
    termination: reencrypt
    destinationCACertificate: |-
      -----BEGIN CERTIFICATE-----
      <backend-ca-cert>
      -----END CERTIFICATE-----
```

### Route troubleshooting

```bash
# Describe the route — shows admission status and host assignment
oc describe route <route-name> -n <namespace>

# Check router pod logs for 503 or backend errors
oc logs -n openshift-ingress \
  -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
  --tail=100

# Verify the service selector matches the pod labels
oc get endpoints <service-name> -n <namespace>

# Test connectivity from inside the cluster
oc run curl-test --image=curlimages/curl --restart=Never --rm -it -- \
  curl -v http://<service-name>.<namespace>.svc.cluster.local:<port>

# Check IngressController status
oc get ingresscontroller default -n openshift-ingress-operator -o yaml
```

**Common Route failures:**

| Symptom | Cause | Fix |
|---|---|---|
| `503 Service Unavailable` | No ready endpoints behind the service | Check pod readiness: `oc get endpoints <svc> -n <ns>` |
| Route admitted but no traffic | Wrong `targetPort` — name vs number mismatch | Match `spec.port.targetPort` to the container port name or number exactly |
| TLS error at browser | cert CN does not match the route host | Verify `spec.tls.certificate` CN/SAN matches `spec.host` |
| Route not admitted | Hostname collision with another route | `oc get routes -A | grep <hostname>` — find the conflicting route |
| `504 Gateway Timeout` | Backend slow; router timeout too short | Add annotation: `haproxy.router.openshift.io/timeout: 120s` |

---

## GitOps and app delivery

### OpenShift GitOps (Argo CD) — platform layout

OpenShift GitOps ships a cluster-scoped Argo CD instance in `openshift-gitops`. Use it for cluster configuration and add-ons. Create namespace-scoped Argo CD instances for app teams to avoid blast radius.

```bash
# Check OpenShift GitOps operator status
oc get csv -n openshift-gitops-operator | grep gitops

# Check the default Argo CD instance
oc get argocd openshift-gitops -n openshift-gitops -o yaml

# List all Applications
oc get applications -n openshift-gitops

# Force a sync
oc patch application <app-name> -n openshift-gitops \
  --type merge -p '{"operation":{"sync":{}}}'
```

### App-of-apps pattern on OpenShift

```yaml
# cluster-config-app.yaml — top-level app pointing at apps/ folder
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

### Sync waves — ordering operators before apps

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-10"   # negative = earlier; operators first
```

Typical wave order:
- Wave -20: namespaces, service accounts, RBAC
- Wave -10: operators (via Subscription)
- Wave 0: operator-managed resources (CRDs ready by now)
- Wave 10: application workloads

### SCC and Argo CD — common footgun

Argo CD's `argocd-application-controller` service account needs `get`/`list`/`watch` on `securitycontextconstraints` at cluster scope, or sync status shows `Unknown` for SCC-bound resources.

```bash
oc adm policy add-cluster-role-to-user \
  system:openshift:scc-review \
  -z argocd-application-controller \
  -n openshift-gitops
```

---

## Security and tenancy

- Prefer OpenShift projects with clear ownership and quota boundaries.
- Define role bindings narrowly; avoid broad cluster-wide permissions for app teams.
- Use image streams or approved registries where governance requires them.
- Document exceptions when workloads need elevated SCCs or privileged access.

### Namespace quota + LimitRange baseline

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: app-team
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
    persistentvolumeclaims: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: container-defaults
  namespace: app-team
spec:
  limits:
    - type: Container
      default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
```

---

## Day-2 operations — upgrades

### Cluster version management

```bash
# Current version and upgrade availability
oc get clusterversion

# Detailed upgrade status
oc describe clusterversion version

# List available upgrade channels and versions
oc get clusterversion version \
  -o jsonpath='{.status.availableUpdates[*].version}' | tr ' ' '\n'

# Check which channel the cluster is on
oc get clusterversion version \
  -o jsonpath='{.spec.channel}'

# Switch channel (e.g. stable-4.14 → stable-4.15)
oc patch clusterversion version --type merge \
  -p '{"spec":{"channel":"stable-4.15"}}'
```

### Pre-upgrade validation checklist

```bash
# Check all operators are healthy before upgrading
oc get clusteroperators | grep -v "True.*False.*False"
# Expected: all operators show Available=True, Progressing=False, Degraded=False

# Check all nodes are Ready
oc get nodes | grep -v Ready

# Check for any pending machine config rollouts
oc get machineconfigpool

# Review upgrade-blocking conditions
oc get clusterversion version -o yaml \
  | grep -A5 "conditions:"

# Check API removals — compare deprecated APIs in use vs target version
oc get apirequestcounts \
  | grep -v "0 " \
  | sort -k3 -rn \
  | head -20
```

### Operator upgrade impact

Operators have their own upgrade lifecycle separate from the cluster. Check operator channel and approval mode before initiating a cluster upgrade:

```bash
# List all operator subscriptions and their approval mode
oc get subscriptions -A \
  -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,CHANNEL:.spec.channel,APPROVAL:.spec.installPlanApproval'

# Check if any InstallPlans are waiting for manual approval
oc get installplan -A | grep Manual

# Approve a pending InstallPlan
oc patch installplan <install-plan-name> -n <namespace> \
  --type merge -p '{"spec":{"approved":true}}'
```

### Post-upgrade validation

```bash
# All cluster operators healthy
oc get clusteroperators

# All nodes updated and Ready
oc get nodes

# MachineConfigPool rolled out
oc get machineconfigpool

# Check workloads for admission failures after SCC policy changes
oc get events -A --field-selector reason=FailedCreate \
  | grep -i scc

# Validate routes still resolve
for route in $(oc get routes -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {end}'); do
  ns=$(echo $route | cut -d/ -f1)
  name=$(echo $route | cut -d/ -f2)
  host=$(oc get route $name -n $ns -o jsonpath='{.spec.host}')
  echo "$ns/$name → $host"
done
```

### Rollback

OpenShift cluster upgrades are not directly reversible once the control plane has moved forward. The safe path is:

1. Hold at the current version until all operators and node pools are healthy
2. If a specific operator breaks, roll back the operator independently via InstallPlan
3. If workloads break due to SCC policy tightening in the new version, fix the SCC grants — do not revert the cluster
4. For catastrophic failures, use etcd backup/restore (only if taken before the upgrade)
