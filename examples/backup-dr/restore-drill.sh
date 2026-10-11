#!/usr/bin/env bash
# examples/backup-dr/restore-drill.sh — prove a Velero backup restores, and time it.
#
# Restores one namespace from the latest completed backup of a schedule (or a
# named backup) into <namespace>-drill in the same cluster, waits for every
# pod to be Ready, and reports the time from start to ready: your measured
# recovery time for that namespace. The drill copy is not reachable from
# outside the cluster: HTTPRoutes and Ingresses are excluded, so it cannot
# claim a production hostname, and Services are not restored as they were (a
# restored LoadBalancer would provision a new public load balancer, a NodePort
# would open a port on every node). Internal copies, ClusterIP or headless with
# the same selector and ports, are recreated from the source namespace so
# in-namespace DNS still resolves. The drill namespace is deleted afterwards
# unless --keep is given.
#
# Usage:
#   bash restore-drill.sh --namespace my-app [--schedule velero-nightly | --backup <name>] [--timeout 900] [--keep]
# Requires: velero CLI, kubectl pointed at the cluster, jq; Velero in namespace "velero".

set -euo pipefail

NS="" SCHEDULE="velero-nightly" BACKUP="" TIMEOUT=900 KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --namespace) NS="${2:?}"; shift 2 ;;
    --schedule) SCHEDULE="${2:?}"; shift 2 ;;
    --backup) BACKUP="${2:?}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$NS" ] || { echo "--namespace is required" >&2; exit 2; }
for bin in velero kubectl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "$bin not found" >&2; exit 2; }
done

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
echo "Restoring $NS from $BACKUP into $DRILL_NS as $RESTORE"
start=$(date +%s)
velero restore create "$RESTORE" \
  --from-backup "$BACKUP" \
  --include-namespaces "$NS" \
  --namespace-mappings "$NS:$DRILL_NS" \
  --exclude-resources httproutes.gateway.networking.k8s.io,ingresses.networking.k8s.io,services,endpoints,endpointslices.discovery.k8s.io \
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

if [ "$KEEP" -eq 0 ]; then
  kubectl delete namespace "$DRILL_NS" --wait=false
  echo "Deleted $DRILL_NS (restored volumes are released with their PVCs)"
fi
