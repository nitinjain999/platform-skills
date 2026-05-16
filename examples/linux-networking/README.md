# Linux & Networking Examples

Status: Stable

Working examples for the `/platform-skills:linux` command — DNS troubleshooting, load balancer diagnostics, VPC connectivity, process and disk analysis, and Kubernetes networking.

## How the Command Works

```
/platform-skills:linux dns
/platform-skills:linux lb
/platform-skills:linux vpc
/platform-skills:linux process
/platform-skills:linux disk
/platform-skills:linux network
/platform-skills:linux security-groups
```

---

## Examples

### dns-troubleshooting.sh

Step-by-step DNS resolution diagnostics inside and outside Kubernetes.

```bash
#!/usr/bin/env bash
# DNS resolution path for Kubernetes pod → service

# 1. Check if CoreDNS pods are running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. Confirm the service exists
kubectl get svc payments-service -n checkout

# 3. Test resolution from inside a pod
kubectl run -it --rm debug --image=busybox:1.36 --restart=Never -- sh
# Inside pod:
nslookup payments-service.checkout.svc.cluster.local
# Expected: returns ClusterIP

# 4. Check /etc/resolv.conf inside the pod
cat /etc/resolv.conf
# Expected: search checkout.svc.cluster.local svc.cluster.local cluster.local

# 5. Check CoreDNS config
kubectl get configmap coredns -n kube-system -o yaml

# 6. Check CoreDNS logs for query errors
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# 7. Test external resolution (confirms CoreDNS forward is working)
nslookup google.com
```

**Common failure causes:**

| Symptom | Most likely cause | Evidence command |
|---|---|---|
| `nslookup` returns `NXDOMAIN` | Service name or namespace wrong in query | `kubectl get svc -A \| grep <name>` |
| `nslookup` times out | CoreDNS pods not running or crashing | `kubectl get pods -n kube-system -l k8s-app=kube-dns` |
| External DNS fails but internal works | CoreDNS forward config missing or wrong | `kubectl get configmap coredns -n kube-system -o yaml` |
| Intermittent resolution failures | CoreDNS memory/CPU limit hit | `kubectl top pods -n kube-system -l k8s-app=kube-dns` |

---

### alb-502-diagnostic.sh

Diagnosing 502 Bad Gateway from an AWS Application Load Balancer when target group shows healthy.

```bash
#!/usr/bin/env bash
# ALB 502 diagnostic — target group healthy but 502 returned

# 1. Confirm target health (look for "healthy" state)
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:eu-central-1:123456789:targetgroup/orders/abc123

# 2. Check ALB access logs for error detail (must have access logging enabled)
# Filter for 502 responses in the last 5 minutes
aws s3 sync s3://my-alb-logs/AWSLogs/123456789/elasticloadbalancing/eu-central-1/$(date +%Y/%m/%d)/ ./alb-logs/
grep " 502 " ./alb-logs/*.log | tail -20

# 3. Check security group: ALB must reach the pod/node on the target port
aws ec2 describe-security-groups --group-ids sg-alb-id sg-node-id

# 4. Check the app is actually listening on the expected port
kubectl exec -it <pod-name> -n orders -- ss -tlnp | grep 8080

# 5. Check pod logs for connection reset or timeout errors
kubectl logs -n orders -l app=orders-api --tail=100 | grep -i "reset\|timeout\|refused"

# 6. Check if the pod readiness probe is passing
kubectl describe pod -n orders -l app=orders-api | grep -A5 "Readiness"
```

**502 root causes in order of frequency:**

1. App not listening on the registered port (wrong `containerPort` or env var override)
2. Security group blocks ALB → node traffic on the NodePort range
3. App returns a response before headers are complete (HTTP/1.0 vs 1.1 mismatch)
4. TLS termination mismatch (ALB expects HTTP, pod returns HTTPS)
5. Readiness probe path wrong — pod marked healthy before app is ready

---

### vpc-connectivity.sh

Diagnosing connectivity between two VPCs connected via VPC peering or Transit Gateway.

```bash
#!/usr/bin/env bash
# VPC peering connectivity checklist

# 1. Confirm peering connection is active
aws ec2 describe-vpc-peering-connections \
  --filters "Name=status-code,Values=active"

# 2. Check route tables on BOTH sides — missing route is the most common cause
# VPC A route table (should have route to VPC B CIDR)
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-aaa" \
  --query 'RouteTables[*].Routes[?GatewayId!=`local`]'

# VPC B route table (should have route to VPC A CIDR)
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-bbb" \
  --query 'RouteTables[*].Routes[?GatewayId!=`local`]'

# 3. Check security groups allow inbound traffic on the target port
aws ec2 describe-security-groups --group-ids sg-target \
  --query 'SecurityGroups[*].IpPermissions'

# 4. Check NACLs — stateless, so both inbound AND outbound rules must allow traffic
aws ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=vpc-bbb"

# 5. Use VPC Reachability Analyzer to confirm path
aws ec2 create-network-insights-path \
  --source <source-eni-id> \
  --destination <dest-eni-id> \
  --protocol tcp \
  --destination-port 8080
```

---

## See Also

- [commands/linux.md](../../commands/linux.md) — full command definition with all modes and diagnostics
- [references/linux-networking.md](../../references/linux-networking.md) — DNS, load balancer, VPC/VNet, and process reference patterns
