# Linux and Networking Reference

Practical guidance for Linux administration and networking fundamentals as they apply to platform engineering: DNS, load balancing, and VPC/network design.

---

## Linux Administration

### Process and Service Management

```bash
# systemd service lifecycle
systemctl status <service>
systemctl start | stop | restart | reload <service>
systemctl enable | disable <service>       # persist across reboots
journalctl -u <service> -f                 # follow logs for a unit
journalctl -u <service> --since "1 hour ago"

# List all active services
systemctl list-units --type=service --state=active

# Check failed units
systemctl --failed
```

### File System and Disk

```bash
# Disk usage
df -hT                        # filesystem type + human-readable sizes
du -sh /var/log/*             # per-directory usage
lsblk                         # block device tree
fdisk -l                      # partition table

# Find large files
find / -xdev -size +500M -printf "%s\t%p\n" | sort -n

# Inode exhaustion (common cause of "no space" with free disk)
df -i
```

### Memory and CPU

```bash
# Memory overview
free -h
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree"

# CPU load
uptime                        # load averages: 1m, 5m, 15m
top -bn1                      # snapshot — useful in scripts
vmstat 1 5                    # 5 samples, 1s interval: cpu/mem/io/swap
mpstat -P ALL 1               # per-core breakdown

# Process investigation
ps aux --sort=-%mem | head -20
ps aux --sort=-%cpu | head -20
lsof -p <pid>                 # open files for a process
strace -p <pid> -c            # syscall summary (attach to running process)
```

### Networking Tools on Linux

```bash
# Interface state
ip addr show
ip link show
ip route show
ss -tulnp                     # listening sockets with process names (replaces netstat)
ss -s                         # summary: total/TCP/UDP counts

# Connectivity
ping -c 4 <host>
traceroute -n <host>          # -n skips reverse DNS for speed
mtr --report <host>           # combines ping + traceroute

# Packet capture
tcpdump -i eth0 -n port 443 -c 100
tcpdump -i any host 10.0.1.5 and port 8080 -w /tmp/capture.pcap

# Bandwidth
iperf3 -s                     # server
iperf3 -c <server-ip>         # client

# DNS from Linux
dig @8.8.8.8 example.com A
dig +short example.com
dig -x 10.0.1.5               # reverse lookup
resolvectl status             # systemd-resolved config and cache state
```

### Kernel and System Parameters

```bash
# View kernel parameters
sysctl -a | grep <keyword>

# Common tuning for high-traffic nodes
sysctl net.core.somaxconn          # listen backlog limit (default 128, set 65535 for load balancers)
sysctl net.ipv4.tcp_max_syn_backlog
sysctl net.ipv4.ip_local_port_range  # ephemeral port range

# Apply without reboot
sysctl -w net.core.somaxconn=65535

# Persist in /etc/sysctl.d/99-platform.conf
echo "net.core.somaxconn = 65535" >> /etc/sysctl.d/99-platform.conf
sysctl --system   # reload all .conf files
```

### User and Permission Management

```bash
# Create service account (no login shell, no home)
useradd --system --no-create-home --shell /usr/sbin/nologin appuser

# File permissions
chmod 640 /etc/app/config.yaml   # owner rw, group r, others none
chown appuser:appgroup /var/run/app

# sudo — minimal privilege
# /etc/sudoers.d/appuser
appuser ALL=(root) NOPASSWD: /usr/bin/systemctl restart app.service

# Check effective permissions
sudo -l -U appuser
```

---

## DNS

### How DNS Resolution Works

```
Client → Recursive Resolver (e.g. 8.8.8.8 or VPC DNS)
       → Root nameserver (.)
       → TLD nameserver (.com)
       → Authoritative nameserver (example.com)
       ← Answer cached at recursive resolver for TTL seconds
```

Platform-relevant implications:
- **TTL governs propagation delay** — lower TTL before planned changes, restore after
- **Negative TTL (NXDOMAIN)** caches non-existence — affects fast DNS fix rollouts
- **VPC DNS resolver** (169.254.169.253 on AWS, 168.63.129.16 on Azure) handles private zone resolution

### Record Types

| Type | Purpose | Example |
|------|---------|---------|
| `A` | IPv4 address | `api.example.com → 10.0.1.5` |
| `AAAA` | IPv6 address | `api.example.com → 2001:db8::1` |
| `CNAME` | Alias to another name | `www → api.example.com` |
| `ALIAS`/`ANAME` | CNAME at zone apex | `example.com → lb.example.com` (AWS Route 53 Alias) |
| `MX` | Mail exchange | priority + mail server |
| `TXT` | Arbitrary text | SPF, DKIM, domain verification |
| `SRV` | Service location | `_grpc._tcp.svc.cluster.local` |
| `PTR` | Reverse lookup | `5.1.0.10.in-addr.arpa → api.example.com` |
| `NS` | Nameserver delegation | which servers are authoritative |
| `SOA` | Zone authority + serial | refresh/retry/expire/minTTL |

### Kubernetes DNS (CoreDNS)

In-cluster DNS follows this pattern:

```
<service>.<namespace>.svc.cluster.local
<pod-ip-dashes>.<namespace>.pod.cluster.local
```

Short names are resolved via the `ndots` search path. A pod has:
```
search default.svc.cluster.local svc.cluster.local cluster.local
ndots: 5
```

A name with fewer than 5 dots is tried against each search domain before a global lookup. This means `api` resolves to `api.default.svc.cluster.local`.

**CoreDNS troubleshooting:**
```bash
# Check CoreDNS pods
kubectl -n kube-system get pods -l k8s-app=kube-dns

# Test resolution from inside a pod
kubectl run -it dnsutils --image=busybox:1.36 --restart=Never -- sh
nslookup kubernetes.default
nslookup <service>.<namespace>

# Check CoreDNS config
kubectl -n kube-system get configmap coredns -o yaml

# Logs
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50
```

### AWS Route 53

**Routing policies:**

| Policy | Use case |
|--------|---------|
| Simple | Single resource, no health checks |
| Weighted | A/B testing, gradual traffic shift |
| Latency | Route to lowest-latency region |
| Failover | Active/passive with health check |
| Geolocation | Route by user country/continent |
| Multivalue Answer | Basic load balancing across up to 8 IPs |

**Private hosted zone** for internal service discovery:
```hcl
resource "aws_route53_zone" "internal" {
  name = "internal.example.com"

  vpc {
    vpc_id = aws_vpc.main.id
  }
}

resource "aws_route53_record" "service" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "payments.internal.example.com"
  type    = "A"
  ttl     = 60
  records = [aws_lb.payments.dns_name]  # use ALIAS for ALB/NLB
}
```

### Azure Private DNS

```hcl
resource "azurerm_private_dns_zone" "internal" {
  name                = "internal.example.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  name                  = "main-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false  # true = auto-register VM hostnames
}
```

---

## Load Balancing

### OSI Layer Comparison

| Layer | Name | What it inspects | Examples |
|-------|------|-----------------|---------|
| L4 | Transport | IP + port only | AWS NLB, Azure Standard LB, HAProxy TCP mode |
| L7 | Application | HTTP host, path, headers, body | AWS ALB, Azure App GW, NGINX, Traefik |

Use L4 when:
- Protocol is not HTTP (gRPC, MySQL, Redis, raw TCP)
- You need TLS passthrough to the backend
- Ultra-low latency / millions of connections

Use L7 when:
- Path-based or host-based routing
- SSL termination at the LB
- Request/response header manipulation
- WAF, rate limiting, auth at the edge

### AWS Load Balancers

**ALB (Application, L7):**
- Routes by host, path, query string, HTTP method, headers
- Native support for gRPC and HTTP/2
- Integrates with Cognito, WAF, Lambda targets
- Use for ingress to EKS (AWS Load Balancer Controller)

**NLB (Network, L4):**
- Static IP per AZ — required when downstream needs a fixed IP
- TLS passthrough or TLS termination
- Preserves client source IP to targets
- Use for non-HTTP services, very high throughput

**Terraform ALB + target group:**
```hcl
resource "aws_lb" "app" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "app" {
  name        = "app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"   # "ip" for EKS pod IPs, "instance" for EC2

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
```

### Kubernetes Ingress and Gateway API

**Ingress (legacy, still common):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: app-svc
                port:
                  number: 8080
  tls:
    - hosts:
        - app.example.com
      secretName: app-tls
```

**HTTPRoute (Gateway API — preferred for new clusters):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app
spec:
  parentRefs:
    - name: main-gateway
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: app-svc
          port: 8080
```

---

## VPCs and Network Design

### CIDR Planning

Rules of thumb:
- `/16` per VPC — 65,536 addresses, enough for large-scale workloads
- `/24` per subnet — 251 usable (AWS/Azure reserve 5 addresses)
- Leave gaps between VPCs if you plan to peer them — overlapping CIDRs cannot be peered
- Reserve a `/8` supernet range for your org (e.g. `10.0.0.0/8`) and carve per environment

**Example allocation:**
```
10.0.0.0/8  — org supernet
  10.0.0.0/16  — production VPC
    10.0.0.0/24  — public subnet (AZ-a)
    10.0.1.0/24  — public subnet (AZ-b)
    10.0.10.0/24 — private subnet (AZ-a)
    10.0.11.0/24 — private subnet (AZ-b)
    10.0.20.0/24 — data subnet (AZ-a)
    10.0.21.0/24 — data subnet (AZ-b)
  10.1.0.0/16  — staging VPC
  10.2.0.0/16  — dev VPC
  10.10.0.0/16 — shared services VPC (DNS, VPN, monitoring)
```

### Subnet Tiers

| Tier | Subnet Type | Route table | What goes here |
|------|-------------|-------------|----------------|
| Public | Public | 0.0.0.0/0 → IGW | Load balancers, NAT GWs, bastion (if any) |
| Private (app) | Private | 0.0.0.0/0 → NAT GW | EKS nodes, EC2 app servers, Lambda |
| Data | Private | no internet route | RDS, ElastiCache, MSK — no outbound internet |

**Never** put database instances in public subnets. **Never** route data-tier subnets to the internet.

### AWS VPC Core Components

```hcl
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true   # required for EKS, RDS, PrivateLink
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "main" })
}

# Internet Gateway (public subnets)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# NAT Gateway (one per AZ for HA)
resource "aws_eip" "nat" {
  for_each = toset(var.availability_zones)
  domain   = "vpc"
}

resource "aws_nat_gateway" "main" {
  for_each      = toset(var.availability_zones)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
}

# Route tables — private subnets use AZ-local NAT GW
resource "aws_route" "private_nat" {
  for_each               = toset(var.availability_zones)
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[each.key].id
}
```

### Security Groups vs NACLs

| | Security Groups | NACLs |
|---|---|---|
| Level | Resource (ENI) | Subnet |
| State | Stateful — return traffic auto-allowed | Stateless — must allow return explicitly |
| Rules | Allow only | Allow and Deny |
| Order | All rules evaluated | Rules evaluated in number order, first match wins |
| Use for | Fine-grained resource access control | Broad subnet-level guards (block CIDR ranges) |

Best practice: use security groups for everything. Use NACLs only to block known-bad CIDRs or as a defence-in-depth layer.

### VPC Peering vs Transit Gateway

| | VPC Peering | Transit Gateway |
|---|---|---|
| Scale | 1:1 connections | Hub-and-spoke, thousands of VPCs |
| Transitive routing | No — A↔B and B↔C does not mean A↔C | Yes |
| Cost | No attachment fee | Per attachment + data processing fee |
| Cross-account | Yes | Yes |
| Use when | < 5 VPCs, simple mesh | Many VPCs, on-prem, centralised egress |

### PrivateLink

PrivateLink exposes a service (behind an NLB) to other VPCs without peering or internet exposure. Use it for:
- Third-party SaaS with a PrivateLink offering
- Sharing internal platform services across accounts (e.g. a central Vault cluster)
- Replacing VPC peering when you only need one-way service access

```hcl
# Producer side — endpoint service behind NLB
resource "aws_vpc_endpoint_service" "platform_vault" {
  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.vault_nlb.arn]
}

# Consumer side — endpoint in consumer VPC
resource "aws_vpc_endpoint" "vault" {
  vpc_id              = var.consumer_vpc_id
  service_name        = aws_vpc_endpoint_service.platform_vault.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vault_endpoint.id]
  private_dns_enabled = true
}
```

### Azure VNet Equivalents

| AWS | Azure |
|-----|-------|
| VPC | VNet |
| Subnet | Subnet |
| Security Group | NSG (Network Security Group) |
| NACL | NSG on subnet (same resource, different attachment) |
| Internet Gateway | No explicit resource — controlled by public IP on resource |
| NAT Gateway | NAT Gateway |
| Transit Gateway | Virtual WAN Hub |
| VPC Peering | VNet Peering |
| PrivateLink | Private Endpoint + Private Link Service |

**Azure NSG rule (Terraform):**
```hcl
resource "azurerm_network_security_rule" "allow_https_inbound" {
  name                        = "allow-https-inbound"
  priority                    = 100          # lower = higher priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}
```

---

## Troubleshooting Checklist

### DNS Not Resolving

1. `dig <name> @<resolver-ip>` — test against specific resolver
2. Check TTL — is the old answer still cached?
3. `resolvectl status` / `cat /etc/resolv.conf` — which resolver is the host using?
4. In Kubernetes: test from inside a pod with `nslookup`; check CoreDNS logs
5. Verify the record exists in the authoritative zone: `dig <name> +trace`

### Cannot Reach a Service

1. `ss -tulnp` on the host — is the service listening on the expected port and interface?
2. `ping` — L3 reachability (ICMP may be blocked; absence of ping ≠ no connectivity)
3. `nc -zv <host> <port>` — L4 TCP connectivity
4. `curl -v http://<host>:<port>/healthz` — L7 HTTP
5. Check security groups / NSGs — source IP, port, protocol all match?
6. Check route table — is there a route to the destination?
7. `traceroute -n <host>` — where does the path break?

### High Latency / Packet Loss

1. `mtr --report <host>` — identify the hop where loss begins
2. Check NAT Gateway or NLB metrics — connection count, processed bytes, error count
3. `ss -s` — is the TCP connection table close to limits?
4. `sysctl net.core.somaxconn` — is the listen backlog saturated?
5. CPU steal time (`vmstat` or `top %st`) — noisy neighbour on hypervisor

### Load Balancer Health Check Failures

1. Test the health check path manually: `curl -v http://<target-ip>:<port>/healthz`
2. Check target group registered targets — are the IPs correct?
3. Security group on targets — does it allow traffic from the LB security group (ALB) or the VPC CIDR (NLB, which uses the node IP)?
4. NLB preserves source IP — targets must allow the client CIDR, not just the NLB IP
