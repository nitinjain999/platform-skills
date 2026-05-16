#!/usr/bin/env bash
# DNS resolution diagnostic script for Kubernetes pods
# Usage: Run from a machine with kubectl access
# Adjust NAMESPACE, SERVICE, and POD_SELECTOR for your environment.

NAMESPACE="${1:-checkout}"
SERVICE="${2:-payments-service}"

echo "=== Step 1: CoreDNS pod health ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns

echo ""
echo "=== Step 2: Service exists in namespace ==="
kubectl get svc "$SERVICE" -n "$NAMESPACE" || echo "MISSING: service $SERVICE not found in $NAMESPACE"

echo ""
echo "=== Step 3: CoreDNS configmap ==="
kubectl get configmap coredns -n kube-system -o yaml

echo ""
echo "=== Step 4: CoreDNS recent logs (last 50 lines) ==="
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

echo ""
echo "=== Step 5: Test resolution from debug pod ==="
echo "Run manually inside the cluster:"
echo "  kubectl run -it --rm debug --image=busybox:1.36 --restart=Never -- nslookup ${SERVICE}.${NAMESPACE}.svc.cluster.local"

echo ""
echo "=== Step 6: CoreDNS resource usage ==="
kubectl top pods -n kube-system -l k8s-app=kube-dns 2>/dev/null || echo "metrics-server not available"
