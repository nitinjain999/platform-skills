#!/usr/bin/env bash
# examples/backup-dr/restore-drill.sh — prove a Velero backup restores, and time it.
#
# Restores one namespace from the latest completed backup of a schedule (or a
# named backup) into <namespace>-drill in the same cluster, waits for every
# pod to be Ready, and reports the time from start to ready: your measured
# recovery time for that namespace.
#
# The drill copy is isolated from production in both directions:
#   - Inbound: HTTPRoutes and Ingresses are excluded, so it cannot claim a
#     production hostname, and Services are not restored as they were (a
#     restored LoadBalancer would provision a new public load balancer, a
#     NodePort would open a port on every node). Internal copies, ClusterIP or
#     headless with the same selector and ports, are recreated from the source
#     namespace so in-namespace DNS still resolves.
#   - Outbound: the restored workloads carry production Secrets and config, so
#     the drill namespace is created before the restore with a default-deny
#     NetworkPolicy. Pods may reach each other and the cluster DNS pods (one
#     namespace, one pod label, DNS ports only), and nothing else: no
#     production database, external API or live queue. Allow test
#     dependencies explicitly with --allow-egress <cidr> (repeatable). The
#     backup's own NetworkPolicies are not restored; policies are additive and
#     one allowing egress would reopen the namespace.
#     This needs a CNI that enforces NetworkPolicy egress (Calico, Cilium, the
#     VPC CNI with network policy enabled, OVN-Kubernetes). Without one, run
#     the drill in a separate cluster instead.
# The drill namespace is deleted when the script exits, on success or failure,
# unless --keep is given (use it to inspect a failed drill; delete it yourself).
#
# DNS defaults match CoreDNS on EKS, GKE and AKS (kube-system, k8s-app=kube-dns).
# OpenShift: --dns-namespace openshift-dns
#            --dns-pod-label dns.operator.openshift.io/daemonset-dns=default
# NodeLocal DNSCache: --node-local-dns 169.254.20.10 (DNS ports to that address only)
#
# Usage:
#   bash restore-drill.sh --namespace my-app [--schedule velero-nightly | --backup <name>]
#                         [--allow-egress 10.20.0.0/24 ...] [--timeout 900] [--keep]
#                         [--dns-namespace kube-system] [--dns-pod-label k8s-app=kube-dns]
#                         [--node-local-dns 169.254.20.10]
# Requires: velero CLI, kubectl pointed at the cluster, jq; Velero in namespace "velero".

set -euo pipefail

NS="" SCHEDULE="velero-nightly" BACKUP="" TIMEOUT=900 KEEP=0
DNS_NS="kube-system" DNS_LABEL="k8s-app=kube-dns" NODE_LOCAL_DNS=""
ALLOW_EGRESS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --namespace) NS="${2:?}"; shift 2 ;;
    --schedule) SCHEDULE="${2:?}"; shift 2 ;;
    --backup) BACKUP="${2:?}"; shift 2 ;;
    --allow-egress) ALLOW_EGRESS+=("${2:?}"); shift 2 ;;
    --timeout) TIMEOUT="${2:?}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --dns-namespace) DNS_NS="${2:?}"; shift 2 ;;
    --dns-pod-label) DNS_LABEL="${2:?}"; shift 2 ;;
    --node-local-dns) NODE_LOCAL_DNS="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$NS" ] || { echo "--namespace is required" >&2; exit 2; }
for bin in velero kubectl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "$bin not found" >&2; exit 2; }
done
case "$DNS_LABEL" in
  *=*) ;;
  *) echo "--dns-pod-label must be key=value" >&2; exit 2 ;;
esac
# Without a match the policy would allow no DNS at all and every pod would fail
# readiness for a reason unrelated to the backup.
if [ -z "$(kubectl -n "$DNS_NS" get pods -l "$DNS_LABEL" -o name)" ]; then
  echo "FAIL: no DNS pods match $DNS_LABEL in $DNS_NS; set --dns-namespace and --dns-pod-label" >&2
  exit 1
fi

DRILL_NS="${NS}-drill"
if kubectl get namespace "$DRILL_NS" >/dev/null 2>&1; then
  echo "FAIL: $DRILL_NS already exists; delete it or pick another namespace" >&2
  exit 1
fi

if [ -z "$BACKUP" ]; then
  # Latest backup created by the schedule. Scheduled backups carry the
  # velero.io/schedule-name label.
  BACKUP="$(kubectl -n velero get backups.velero.io -l "velero.io/schedule-name=$SCHEDULE" \
    --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')"
  [ -n "$BACKUP" ] || { echo "FAIL: no backup found for schedule $SCHEDULE" >&2; exit 1; }
fi
phase="$(kubectl -n velero get backups.velero.io "$BACKUP" -o jsonpath='{.status.phase}')"
if [ "$phase" != "Completed" ]; then
  echo "FAIL: backup $BACKUP is $phase, not Completed; a partial backup is not a restore point" >&2
  exit 1
fi

RESTORE="drill-${NS}-$(date -u +%Y%m%d%H%M%S)"

# From here on the drill namespace may exist with production Secrets in it, so
# every exit path removes it unless --keep was asked for.
cleanup() {
  rc=$?
  if [ "$KEEP" -eq 1 ]; then
    echo "Kept $DRILL_NS (--keep); delete it with: kubectl delete namespace $DRILL_NS" >&2
  elif kubectl get namespace "$DRILL_NS" >/dev/null 2>&1; then
    kubectl delete namespace "$DRILL_NS" --wait=false >&2 || rc=1
    echo "Deleted $DRILL_NS (restored volumes are released with their PVCs)" >&2
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Create the drill namespace before the restore, so no restored pod ever runs
# without the egress policy. Velero restores into an existing namespace and
# leaves it as it is, so copy the source namespace's labels (mesh injection,
# Pod Security level) to keep the drill faithful.
kubectl get namespace "$NS" -o json | jq --arg ns "$DRILL_NS" '
  {apiVersion: "v1", kind: "Namespace",
   metadata: {name: $ns,
              labels: ((.metadata.labels // {})
                       | del(."kubernetes.io/metadata.name")
                       + {"platform-skills.io/restore-drill": "true"})}}' | kubectl apply -f -

# Default deny in both directions. Allowed: traffic between pods in the drill
# namespace; DNS ports to the DNS pods only, selected by namespace name and pod
# label (an empty namespaceSelector would let pods reach anything in any
# namespace listening on those ports); NodeLocal DNSCache's address, DNS ports
# only, when --node-local-dns is set; and each --allow-egress CIDR. Port 53 is
# CoreDNS's pod port, 5353 OpenShift DNS's: NetworkPolicy matches the pod port
# after Service translation.
jq -n --arg ns "$DRILL_NS" --arg dns_ns "$DNS_NS" --arg dns_label "$DNS_LABEL" --arg nodelocal "$NODE_LOCAL_DNS" '
  $ARGS.positional as $cidrs
  | [{protocol: "UDP", port: 53}, {protocol: "TCP", port: 53},
     {protocol: "UDP", port: 5353}, {protocol: "TCP", port: 5353}] as $dns_ports
  | ($dns_label | index("=")) as $i
  | {apiVersion: "networking.k8s.io/v1", kind: "NetworkPolicy",
     metadata: {name: "restore-drill-isolation", namespace: $ns},
     spec: {podSelector: {},
            policyTypes: ["Ingress", "Egress"],
            ingress: [{from: [{podSelector: {}}]}],
            egress: ([{to: [{podSelector: {}}]},
                      {to: [{namespaceSelector: {matchLabels: {"kubernetes.io/metadata.name": $dns_ns}},
                             podSelector: {matchLabels: {($dns_label[:$i]): $dns_label[$i+1:]}}}],
                       ports: $dns_ports}]
                     + (if $nodelocal != ""
                        then [{to: [{ipBlock: {cidr: (($nodelocal | split("/")[0]) + "/32")}}],
                               ports: [{protocol: "UDP", port: 53}, {protocol: "TCP", port: 53}]}]
                        else [] end)
                     + (if ($cidrs | length) > 0
                        then [{to: [$cidrs[] | {ipBlock: {cidr: .}}]}]
                        else [] end))}}' \
  --args ${ALLOW_EGRESS[@]+"${ALLOW_EGRESS[@]}"} | kubectl apply -f -

echo "Restoring $NS from $BACKUP into $DRILL_NS as $RESTORE"
start=$(date +%s)
# NetworkPolicies are excluded: they are additive, and a restored policy that
# allows egress would undo restore-drill-isolation.
velero restore create "$RESTORE" \
  --from-backup "$BACKUP" \
  --include-namespaces "$NS" \
  --namespace-mappings "$NS:$DRILL_NS" \
  --exclude-resources httproutes.gateway.networking.k8s.io,ingresses.networking.k8s.io,services,endpoints,endpointslices.discovery.k8s.io,networkpolicies.networking.k8s.io \
  --wait

rphase="$(kubectl -n velero get restores.velero.io "$RESTORE" -o jsonpath='{.status.phase}')"
if [ "$rphase" != "Completed" ]; then
  echo "FAIL: restore $RESTORE ended $rphase" >&2
  velero restore describe "$RESTORE" --details >&2 || true
  exit 1
fi

# Internal-only Services: type ClusterIP (headless stays headless), no node
# ports, no load balancer fields. ExternalName and selector-less Services are
# skipped; their endpoints would point at production.
kubectl -n "$NS" get services -o json | jq --arg ns "$DRILL_NS" '
  {apiVersion: "v1", kind: "List", items: [
    .items[]
    | select(.spec.selector != null and .spec.type != "ExternalName")
    | {apiVersion: "v1", kind: "Service",
       metadata: {name: .metadata.name, namespace: $ns, labels: (.metadata.labels // {})},
       spec: ({type: "ClusterIP",
               selector: .spec.selector,
               ports: [(.spec.ports // [])[] | del(.nodePort)],
               publishNotReadyAddresses: (.spec.publishNotReadyAddresses // false)}
              + (if .spec.clusterIP == "None" then {clusterIP: "None"} else {} end))}
  ]}' | kubectl apply -f -

if ! kubectl -n "$DRILL_NS" wait --for=condition=Ready pods --all --timeout="${TIMEOUT}s"; then
  echo "FAIL: pods in $DRILL_NS not Ready within ${TIMEOUT}s" >&2
  kubectl -n "$DRILL_NS" get pods -o wide >&2 || true
  exit 1
fi
end=$(date +%s)
echo "PASS: $NS restored from $BACKUP and Ready in $((end - start))s (measured recovery time)"
