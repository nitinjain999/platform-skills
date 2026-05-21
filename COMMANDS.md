# Skill Commands — Detailed Usage Guide

Every `/platform-skills:<command>` slash command available in Claude Code, with all modes, what to pass, and what to expect back.

## Prerequisites

```bash
claude plugin install platform-skills
# Then restart Claude Code
```

Commands work in any conversation — type the slash command or describe your problem and the skill activates automatically.

---

## Table of Contents

| Command | What it's for |
|---------|--------------|
| [/platform-skills:review](#platform-skillsreview) | Production-readiness review of any config |
| [/platform-skills:debug](#platform-skillsdebug) | Structured troubleshooting for any symptom |
| [/platform-skills:terraform](#platform-skillsterraform) | Terraform validation pipeline + blast radius |
| [/platform-skills:gitops](#platform-skillsgitops) | Flux CD / Argo CD reconciliation issues |
| [/platform-skills:linkerd](#platform-skillslinkerd) | Linkerd mTLS, injection, policy, multi-cluster |
| [/platform-skills:linux](#platform-skillslinux) | Linux, DNS, load balancing, VPC/VNet, networking |
| [/platform-skills:helmcheck](#platform-skillshelmcheck) | Helm chart scaffold, review, security audit |
| [/platform-skills:commit](#platform-skillscommit) | Conventional commit message generation |
| [/platform-skills:observability](#platform-skillsobservability) | Instrument, alert, dashboard, load test, capacity |
| [/platform-skills:opa](#platform-skillsopa) | OPA/Conftest Rego policy generate, test, validate |
| [/platform-skills:kyverno](#platform-skillskyverno) | Kyverno policy generate, test, audit, debug, migrate |
| [/platform-skills:compliance](#platform-skillscompliance) | SOC 2 gap analysis and Terraform remediation |
| [/platform-skills:datadog](#platform-skillsdatadog) | Datadog setup, APM, monitors, SLOs, incidents |
| [/platform-skills:dynatrace](#platform-skillsdynatrace) | Dynatrace Operator, OneAgent, SLOs, incidents |
| [/platform-skills:document](#platform-skillsdocument) | Docstrings, OpenAPI specs, docs sites, guides |
| [/platform-skills:mcp](#platform-skillsmcp) | MCP server scaffold, review, debug |
| [/platform-skills:product](#platform-skillsproduct) | DevEx, RFC/ADR, post-mortems, capacity, cost |
| [/platform-skills:pr-review](#platform-skillspr-review) | Comprehensive PR risk review |
| [/platform-skills:triage](#platform-skillstriage) | Triage and resolve PR comments |
| [/platform-skills:keda](#platform-skillskeda) | KEDA ScaledObject/ScaledJob — generate, debug, review, scale |
| [/platform-skills:self-improve](#platform-skillsself-improve) | Bootstrap, log, review, or promote agent self-improvement entries |
| [/platform-skills:chaos](#platform-skillschaos) | Install Litmus Chaos or Chaos Mesh, generate fault experiments, schedule chaos, run GameDay, debug, report |
| [/platform-skills:dora](#platform-skillsdora) | Instrument DORA metrics, generate Grafana dashboards, benchmark against performance bands, debug metric gaps |
| [/platform-skills:awesome-docs](#platform-skillsawesome-docs) | Generate animated demo docs, convert existing Markdown, update diagrams, diff for staleness, audit quality, preview, export |

---

## `/platform-skills:review`

**What it does:** Senior-engineer production-readiness review of any platform config. Evaluates correctness → security → operational safety → deprecations. Returns findings as Critical / Improvement / Note.

**Works on:** Kubernetes manifests, Terraform modules, GitHub Actions workflows, Helm values, RBAC configs, network policies, Dockerfiles, any YAML.

```
/platform-skills:review [paste file content or describe what to review]
```

**What gets checked:**

| Priority | Checks |
|----------|--------|
| 1. Correctness | API versions, required fields, label/namespace consistency, will it do what it intends? |
| 2. Security | Least-privilege RBAC/IAM, no plaintext secrets, non-root containers, SHA-pinned actions, scoped IAM |
| 3. Operational safety | Rollback path, blast radius, resource limits, liveness/readiness probes, GitOps prune behaviour |
| 4. Deprecations | Deprecated APIs, action versions, fields that will break on next minor version |

**Examples:**

Review a Deployment manifest — paste it inline:
```
/platform-skills:review
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-service
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: app
          image: my-registry/orders:latest
          env:
            - name: DB_PASSWORD
              value: "hunter2"
```

Review a GitHub Actions workflow file by path:
```
/platform-skills:review .github/workflows/deploy.yml
```

Review a Terraform IAM module inline:
```
/platform-skills:review
resource "aws_iam_role_policy" "app" {
  policy = jsonencode({
    Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
  })
}
```

Review Helm values against a specific chart:
```
/platform-skills:review my values.yaml for the ingress-nginx chart — are resource limits set? Is the service account locked down?
```

**What comes back:** A structured report grouped by severity. Critical items block merge; Improvements are non-blocking; Notes are informational.

---

## `/platform-skills:debug`

**What it does:** Structured troubleshooting using a 6-step framework: classify layer → collect evidence → root-cause hypothesis → fix → validate → rollback. Forces you to gather evidence before applying a fix.

**Works on:** Any platform symptom across Terraform, Kubernetes, OpenShift, Flux CD, Argo CD, Linkerd, GitHub Actions, AWS/Azure, Secrets management.

```
/platform-skills:debug [symptom or error message]
```

**The 6-step output you get:**

1. **Layer classification** — which system owns this problem (Flux reconciliation? K8s scheduling? AWS IAM?)
2. **Evidence to collect** — exact commands with flags, namespaces, resource names from your description
3. **Root-cause hypothesis** — most likely cause with reasoning; ranked if multiple are plausible
4. **Proposed fix** — exact config change, command, or patch with before/after
5. **Validation** — commands to confirm the fix worked
6. **Rollback** — how to safely undo if validation fails

**Examples:**

Pod stuck in CrashLoopBackOff:
```
/platform-skills:debug orders-service pod CrashLoopBackOff: exit code 137
```

Flux reconciliation not picking up merged changes:
```
/platform-skills:debug Flux Kustomization stuck in NotReady — "context deadline exceeded" — changes merged 20 minutes ago but cluster not updated
```

GitHub Actions OIDC failing:
```
/platform-skills:debug GitHub Actions OIDC error: "Error assuming role with web identity: not authorized to perform sts:AssumeRoleWithWebIdentity"
```

Mysterious 503s after a deploy:
```
/platform-skills:debug 503 errors spiked immediately after deploying v2.3.0 of payments-service, rolling back didn't fully stop them
```

AWS resource creation failing:
```
/platform-skills:debug Terraform apply fails: "Error creating IAM role: LimitExceeded: Cannot exceed quota for InstanceSessionsPerInstanceProfile: 1"
```

---

## `/platform-skills:terraform`

**What it does:** Full Terraform review covering the validation pipeline, blast radius analysis, IAM/security audit, state impact, and module design — in that order.

```
/platform-skills:terraform [paste terraform code, plan output, or describe the change]
```

**The 6-section output:**

| Section | What it covers |
|---------|---------------|
| 1. Validation pipeline | fmt → validate → tflint → tfsec/checkov — pass/fail per gate with exact errors |
| 2. Blast radius | What gets created/modified/destroyed, what gets **replaced** (destructive), downstream dependencies, mid-apply failure impact |
| 3. IAM and security | Wildcard actions/resources, default_tags enforcement, sensitive variables, state backend encryption |
| 4. State impact | Migration requirements, unmanaged resources that could conflict, state isolation by environment |
| 5. Module design | Variable validation blocks, typed outputs, provider placement in caller not module |
| 6. Recommended actions | Exact HCL snippets for each fix |

**Examples:**

Review an IAM policy for wildcards:
```
/platform-skills:terraform
resource "aws_iam_policy" "app" {
  name = "app-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = "*"
    }]
  })
}
```

Blast radius check before applying:
```
/platform-skills:terraform I'm about to run terraform apply on a change that modifies aws_db_subnet_group — what could break and how do I validate it?
```

Review a Terraform plan output:
```
/platform-skills:terraform [paste output of terraform plan]
```

Check a module for reuse quality:
```
/platform-skills:terraform review my EKS module — does it follow module design best practices? Are variables validated?
```

Check state isolation strategy:
```
/platform-skills:terraform we have one state file for all environments in s3://company-tfstate — is this a problem?
```

---

## `/platform-skills:gitops`

**What it does:** Flux CD and Argo CD reconciliation troubleshooting. Classifies by layer (source → artifact → reconciliation → runtime), provides exact evidence commands, and gives a fix with rollback.

```
/platform-skills:gitops [describe the GitOps symptom, paste flux/argocd output, or share a manifest]
```

**Flux CD layers diagnosed:**

| Layer | What it covers |
|-------|---------------|
| Source | GitRepository, OCIRepository, HelmRepository unreachable; auth failures |
| Artifact | Kustomization build errors, HelmChart render failures, path not found |
| Reconciliation | Kustomization apply conflicts, HelmRelease install/upgrade stuck, dependency ordering |
| Runtime | Pod health check failures, hook timeouts, prune-deleted resources |

**Argo CD layers diagnosed:**

| Layer | What it covers |
|-------|---------------|
| Source | Repo credentials, branch/path misconfiguration |
| Diff | ignoreDifferences collisions, server-side apply drift |
| Sync | Sync waves, resource hooks, namespace creation ordering |
| Health | Custom health checks, resource status not propagating |

**Examples:**

Flux Kustomization NotReady:
```
/platform-skills:gitops flux get kustomizations -A shows apps kustomization NotReady: "dependency not found: infrastructure"
```

HelmRelease stuck on upgrade:
```
/platform-skills:gitops HelmRelease orders-service stuck in "upgrade retries exhausted" — error: "values don't match schema"
```

Argo CD perpetually OutOfSync:
```
/platform-skills:gitops ArgoCD application shows OutOfSync despite successful manual sync — sync keeps firing every 3 minutes
```

Image automation not updating:
```
/platform-skills:gitops Flux ImageUpdateAutomation is not pushing updated image tags to Git — ImagePolicy shows correct latest tag
```

Rollback a bad HelmRelease:
```
/platform-skills:gitops how do I safely suspend a HelmRelease, roll back to the previous chart version, and then re-enable reconciliation?
```

---

## `/platform-skills:linkerd`

**What it does:** Linkerd-specific diagnostics across 8 problem classes, with exact `linkerd` CLI evidence commands, root-cause hypothesis, fix, and validation using `linkerd viz edges` / `linkerd check`.

```
/platform-skills:linkerd [describe the Linkerd symptom or paste linkerd check / viz output]
```

**Problem classes:**

| Class | What it diagnoses |
|-------|-----------------|
| Injection | Proxies not being injected; annotation vs namespace annotation conflicts |
| mTLS | Edges showing plaintext; certificate expiry; trust anchor mismatch |
| Authorization policy | Traffic denied by Server/AuthorizationPolicy; identity string mismatches |
| Observability | Missing metrics; PodMonitor selector not matching; linkerd viz not showing data |
| Traffic management | HTTPRoute not splitting traffic; retries not firing; timeout not respected |
| Multi-cluster | Mirrored services unreachable; gateway health; firewall blocking port 4143 |
| Performance | High proxy latency; proxy CPU/memory pressure |
| Control plane | identity/destination/proxy-injector component failures |

**Evidence commands provided:**
```bash
linkerd check
linkerd check --proxy
linkerd viz edges deployment -n <namespace>
linkerd viz stat deploy -n <namespace>
linkerd viz tap deploy/<name> -n <namespace>
kubectl get pods -n <ns> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.linkerd\.io/proxy-version}{"\n"}{end}'
kubectl get secret linkerd-identity-issuer -n linkerd -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

**Examples:**

mTLS not working between services:
```
/platform-skills:linkerd linkerd viz edges shows plaintext between orders-service and payments-service
```

Proxy injection not happening:
```
/platform-skills:linkerd pods in the checkout namespace are not getting the linkerd-proxy sidecar after I added the namespace annotation
```

Traffic not splitting on HTTPRoute:
```
/platform-skills:linkerd HTTPRoute for canary deploy is configured 90/10 but all traffic is going to stable — no traffic to canary pods
```

Multi-cluster service unreachable:
```
/platform-skills:linkerd mirrored service payments-service-remote is unreachable from the primary cluster — gateway shows healthy but curl times out
```

Certificate expiry:
```
/platform-skills:linkerd linkerd check shows "Certificate not yet valid" on the identity issuer — cert renews in 2 days but already failing
```

---

## `/platform-skills:linux`

**What it does:** Linux administration and networking diagnostics across 7 topic areas. Each topic has its own structured framework. Always ends with a validation command and rollback.

```
/platform-skills:linux [topic: dns | lb | vpc | process | disk | network | security-groups | troubleshoot]
```

**Topic frameworks:**

### `dns`
Walks the resolution path client → resolver → authoritative; identifies the break; provides exact `dig`/`nslookup` commands; covers CoreDNS health inside Kubernetes clusters, `ndots` behaviour, and search domain issues.

```
/platform-skills:linux dns pod cannot resolve payments-service.checkout.svc.cluster.local
```
```
/platform-skills:linux dns external DNS propagation delay after updating Route 53 record — TTL is 300s but clients still seeing old IP after 10 minutes
```

### `lb`
Diagnoses L4 vs L7 choice, health check failures, routing issues, target group type, source IP preservation on NLB.

```
/platform-skills:linux lb ALB returning 502 — target group shows healthy but upstream still getting 502s intermittently
```
```
/platform-skills:linux lb should I use ALB or NLB for a gRPC service? What are the implications?
```

### `vpc`
Subnet tier review, route table correctness, IGW/NAT GW attachment, security group rules. Peering vs Transit Gateway scale/cost trade-off. PrivateLink producer/consumer placement.

```
/platform-skills:linux vpc EKS pods in private subnet cannot reach ECR — what route and security group changes are needed?
```
```
/platform-skills:linux vpc 12 VPCs need to talk to each other — peering or Transit Gateway?
```

### `process`
Crashed services, resource exhaustion, misconfigurations. Provides `systemctl`, `journalctl`, `ps`, `lsof`, `strace` commands. Covers memory (`free -h`, `/proc/meminfo`) and CPU (`vmstat`, `mpstat`).

```
/platform-skills:linux process nginx keeps restarting — how do I find the root cause and make the fix survive a reboot?
```
```
/platform-skills:linux process Java process OOMKilled by the OS but -Xmx is set to 2g and node has 8g RAM
```

### `disk`
Checks both space (`df -hT`) and inodes (`df -i`). Finds large files with `du -sh`, identifies deleted-but-open files with `lsof | grep deleted`.

```
/platform-skills:linux disk /var/log is at 95% — how do I find what's consuming space without taking down the service?
```
```
/platform-skills:linux disk disk shows full but df shows 80% — how to find the "missing" space?
```

### `network`
Full connectivity ladder: L3 (`ping`) → L4 (`nc -zv`) → L7 (`curl -v`). Interface state, route table, socket stats. Kernel tuning for high-traffic services (`somaxconn`, `tcp_max_syn_backlog`, `ip_local_port_range`).

```
/platform-skills:linux network two pods can ping each other but TCP connection is refused on port 8080 — same namespace, same node
```
```
/platform-skills:linux network high connection reset rate under load — suspect kernel TCP backlog limits
```

### `security-groups`
Maps traffic flow source → SG on LB → SG on target → NACL. Identifies missing or incorrect rules. Notes NLB source IP preservation behaviour.

```
/platform-skills:linux security-groups ALB to ECS task health check failing — security group rule looks correct but target health shows unhealthy
```
```
/platform-skills:linux security-groups NLB target is unhealthy but the same target passes curl from within the VPC
```

### `troubleshoot`
General-purpose structured checklist when you don't know the topic. Classifies symptom first, then applies the appropriate framework.

```
/platform-skills:linux troubleshoot service was reachable 30 minutes ago, now timing out — no recent deploys
```

---

## `/platform-skills:helmcheck`

**What it does:** Three modes — scaffold a production-ready chart from scratch, review an existing chart for structural issues, or run a security audit.

```
/platform-skills:helmcheck [create <workload-type> | review | security] [chart path or description]
```

---

### Mode: `create`

Generates a complete, production-ready Helm chart based on workload type.

| Workload type | Resources generated |
|---------------|-------------------|
| Web service | Deployment + Service + Ingress |
| Worker | Deployment only (no Service) |
| CronJob | CronJob + ServiceAccount |
| Stateful | StatefulSet + PVC + Headless Service |

**What gets generated:**
- `Chart.yaml` with name, description, type, version, appVersion
- `_helpers.tpl` with all 6 standard helpers: `name`, `fullname`, `chart`, `labels`, `selectorLabels`, `serviceAccountName` — `selectorLabels` correctly excludes `app.kubernetes.io/version` (immutable after creation)
- `values.yaml` — every key commented, defaults that work with zero overrides, hardened `securityContext` (non-root, readOnlyRootFilesystem, drop ALL), resource requests+limits present
- `deployment.yaml`, `service.yaml`, `serviceaccount.yaml` (with `automountServiceAccountToken: false`)
- Optional: `ingress.yaml`, `hpa.yaml` (autoscaling/v2), `pdb.yaml` (policy/v1), `networkpolicy.yaml`
- Validation pipeline: `helm lint --strict`, `helm template --debug`, `kubeconform -strict`

**Examples:**

```
/platform-skills:helmcheck create web service for a Node.js REST API — needs ingress, HPA, and network policy
```
```
/platform-skills:helmcheck create worker for a Python background job that reads from SQS — no inbound traffic
```
```
/platform-skills:helmcheck create stateful for PostgreSQL with PVC and headless service
```

---

### Mode: `review`

Checks a chart against a severity table. Reports Critical/High/Medium/Low findings with exact fixes.

**Checks include:** missing `_helpers.tpl`, no resource limits, no probes, hardcoded image tags, wrong label immutability, missing NOTES.txt, `automountServiceAccountToken: true`, undocumented values.

```
/platform-skills:helmcheck review ./charts/orders-service
```
```
/platform-skills:helmcheck review — the chart has no liveness probes and I suspect the values.yaml has secrets hardcoded
```

---

### Mode: `security`

Full security audit across pod security, RBAC, network, and secrets.

**Checks include:**
- Pod: no `securityContext`, running as root, `readOnlyRootFilesystem: false`, capabilities not dropped, `privileged: true`, `allowPrivilegeEscalation: true`
- RBAC: missing dedicated ServiceAccount, `automountServiceAccountToken: true`, ClusterRole used where Role would do, wildcard verbs
- Network: missing NetworkPolicy, `hostNetwork/hostPID/hostIPC: true`
- Secrets: plaintext in values.yaml defaults, missing PDB

```
/platform-skills:helmcheck security ./charts/payments-service
```
```
/platform-skills:helmcheck security — our chart runs as root and mounts the host docker socket, help me fix it
```

---

## `/platform-skills:commit`

**What it does:** Generates, validates, and stages [Conventional Commits](https://www.conventionalcommits.org/) messages. Four modes: analyze → generate → stage → validate.

```
/platform-skills:commit [analyze|generate|stage|validate] [optional: type/scope override or description]
```

**Commit message format:**
```
<type>(<scope>): <imperative subject — 72 chars max>

<body — explains WHY, wraps at 72 chars>

<footers — BREAKING CHANGE:, Fixes #N>
```

---

### Mode: `analyze`

Inspects staged diff (or unstaged if nothing staged). Groups files by logical concern, detects type and scope, flags breaking changes.

**Type detected from:**

| Type | When |
|------|------|
| `feat` | New capability or behavior added |
| `fix` | Corrects broken behavior |
| `refactor` | Restructures without changing behavior |
| `perf` | Measurably improves performance |
| `test` | Tests only |
| `docs` | Documentation only |
| `chore` | Deps, build tooling, no production effect |
| `ci` | CI/CD pipeline changes |
| `revert` | Reverts a prior commit |

**Returns:** detected type, inferred scope, breaking change flag, one-line WHY summary.

```
/platform-skills:commit analyze
```
```
/platform-skills:commit analyze — I changed the auth middleware to reject tokens missing the 'sub' claim
```

---

### Mode: `generate`

Runs `analyze` internally, then writes the full commit message — subject (imperative mood, WHY-focused, ≤72 chars), body, and footers.

```
/platform-skills:commit generate
```
```
/platform-skills:commit generate feat auth — I added OIDC login support with PKCE flow
```
```
/platform-skills:commit generate — breaking change, removed the /v1/orders endpoint
```

**Example output:**
```
feat(auth): add OIDC login with PKCE flow

Previous password-based login could not support SSO providers. PKCE
prevents auth code interception on public clients without requiring
a client secret.

BREAKING CHANGE: /api/auth/login now returns an authorization_url
instead of a session token. Clients must redirect to this URL.

Closes #142
```

---

### Mode: `stage`

Lists all modified files, groups them by logical change, identifies unrelated changes that should be separate commits, and stages the chosen group.

```
/platform-skills:stage
```

**Useful when:** you've changed multiple unrelated things and want clean atomic commits.

**Example:**
```
/platform-skills:commit stage
```
Output groups might be:
- Group A: `src/auth/oidc.ts`, `src/auth/oidc.test.ts` → `feat(auth): add OIDC`
- Group B: `package.json`, `package-lock.json` → `chore(deps): bump axios to 1.7.0`
- Group C: `README.md` → `docs: document OIDC setup`

---

### Mode: `validate`

Checks an existing commit message against the full spec. Reports PASS or exact violations with the corrected line.

**Rules checked:** valid type, lowercase scope, `!` only with `BREAKING CHANGE` footer, subject starts lowercase, no trailing period, ≤72 chars, blank line before body, body wraps at 72 chars, well-formed footers.

```
/platform-skills:commit validate "Fix: updated auth service"
```
```
/platform-skills:commit validate "$(git log -1 --format=%B)"
```

---

## `/platform-skills:observability`

**What it does:** Add the three pillars to a service (logs/metrics/traces), build Grafana dashboards, write Prometheus alerting rules, design k6 load tests, or estimate capacity and HPA configuration.

```
/platform-skills:observability [instrument|dashboard|alert|loadtest|capacity] [service description]
```

---

### Mode: `instrument`

Adds structured logging, RED metrics, and OpenTelemetry tracing to a service. Asks for: language/framework, existing logging library, metrics backend (Prometheus/Datadog/CloudWatch), tracing backend (Jaeger/Tempo/OTLP).

**What gets generated:**
- Structured JSON logging with correlation IDs (Pino for Node.js, structlog for Python)
- RED metrics: `http_requests_total` counter + `http_request_duration_seconds` histogram, labelled by route and status
- OpenTelemetry tracing with span attributes on critical paths
- `/metrics` Prometheus scrape endpoint
- `/healthz` and `/readyz` health check endpoints
- List of what NOT to log (passwords, tokens, PII)

```
/platform-skills:observability instrument a Node.js Express API — Prometheus metrics, Tempo tracing, Pino logging
```
```
/platform-skills:observability instrument a Python FastAPI service — I'm already using structlog, add RED metrics and OpenTelemetry spans for the payment and order endpoints
```

---

### Mode: `dashboard`

Generates a Grafana dashboard using RED (request-based services) or USE (resource-based infrastructure) method.

**Panels generated:** request rate (req/s), error rate (%), p50/p95/p99 latency (ms), active connections, queue depth. Threshold lines at SLO boundaries, template variables for `env` and `service`.

```
/platform-skills:observability dashboard for the orders-service — RED method, SLO is 99.9% availability and p99 < 500ms
```
```
/platform-skills:observability dashboard USE method for the Postgres database — CPU, memory, disk I/O, connection pool
```

---

### Mode: `alert`

Writes Prometheus alerting rules using `rate()` over 5-minute windows, with `for:` duration, `severity` label, and `runbook` annotation.

**Alert design enforced:**
- Page on symptoms (error rate, latency) — not causes (CPU %)
- Every alert must have a `runbook` annotation URL
- SLO burn-rate alerts derived from error budget, not raw thresholds

```
/platform-skills:observability alert write SLO burn-rate alerts for orders-service — 99.9% availability target, 30-day window
```
```
/platform-skills:observability alert high p99 latency alert for the payments-service — critical at 1s, warning at 500ms, fire after 5 minutes
```

---

### Mode: `loadtest`

Writes a k6 load test with ramp-up → steady-state → ramp-down stages, thresholds matching the SLO, and `check()` assertions on status code and response time.

Asks for: target endpoint, expected peak RPS, SLO thresholds (p95 latency, error rate).

```
/platform-skills:observability loadtest for POST /orders — peak 500 RPS, p95 must be under 200ms, error rate under 0.1%
```
```
/platform-skills:observability loadtest simulate 2000 concurrent users on the checkout flow — ramp up over 5 minutes
```

---

### Mode: `capacity`

Estimates replica count, resource requests/limits, and HPA configuration based on expected load.

**Formula used:** `replicas = ceil((peak_rps × avg_latency_s) / target_concurrency_per_pod)` + 50% headroom. HPA CPU target ≤ 60%.

```
/platform-skills:observability capacity orders-service handles 200 RPS at p99 150ms, expecting 3× growth — what are the resource requests and HPA settings?
```
```
/platform-skills:observability capacity current 4 pods at 70% CPU at 1000 RPS — what's the right HPA min/max and target utilisation?
```

---

## `/platform-skills:opa`

**What it does:** Generate Rego policies, write unit tests, run the full validation pipeline (fmt → regal → conftest verify), explain policies in plain English, or debug why a rule isn't firing.

```
/platform-skills:opa [generate|test|validate|explain|debug] [policy description or file path]
```

---

### Mode: `generate`

Writes a production-ready Rego policy from a description. Asks for: target resource type (Terraform HCL/plan JSON, Kubernetes manifest, GitHub Actions, Dockerfile), rule logic, and whether a named package is needed.

**What gets generated:**
- METADATA block: `title`, `description`, `authors`, `entrypoint: true`
- `package <namespace>` — named packages for multi-domain repos (`package terraform.iam`, `package k8s.pods`)
- `import rego.v1`
- `deny` for hard failures, `warn` for advisory, `violation` for Gatekeeper
- Descriptive `msg` including resource name and remediation hint
- Conftest command to test it

```
/platform-skills:opa generate a policy that denies Kubernetes Deployments without resource limits set on all containers
```
```
/platform-skills:opa generate a Terraform policy that denies S3 buckets with public ACLs and warns if versioning is not enabled
```
```
/platform-skills:opa generate a policy for GitHub Actions workflows that warns if actions are not pinned to a SHA commit
```

---

### Mode: `test`

Writes `_test.rego` unit tests for a given policy with minimal focused fixtures.

**Structure generated:**
- Package: `package <namespace>_test`
- Imports policy under test: `import data.<namespace>`
- For each `deny`/`warn` rule: a positive test (`test_deny_*`, asserts count > 0) and a negative test (`test_allow_*`, asserts count == 0)
- Helper functions to build input fixtures for each case
- Command: `conftest verify --policy <dir>`

```
/platform-skills:opa test write unit tests for my S3 encryption policy
```
```
/platform-skills:opa test — [paste policy file] — generate tests for all deny and warn rules
```

---

### Mode: `validate`

Runs the full 5-step validation pipeline in order. Fixes each stage before proceeding to the next.

| Step | Tool | What it catches |
|------|------|----------------|
| 1. Format check | `conftest fmt --check` | Inconsistent indentation, non-canonical formatting |
| 2. Auto-format | `conftest fmt` | Rewrites files in place if check failed |
| 3. Lint | `regal lint` | Style violations, `no-defined-entrypoint`, unused variables |
| 4. Unit tests | `conftest verify --policy` | Logic correctness against fixtures |
| 5. Integration test | `conftest test --policy <dir> <input-files>` | Real input parsing against actual files |

```
/platform-skills:opa validate ./policies
```
```
/platform-skills:opa validate — regal is reporting "no-defined-entrypoint" on all my files, how do I fix it?
```

---

### Mode: `explain`

Translates Rego into plain English, rule by rule. Maps each `input.<field>` to the actual resource attribute being read. Notes `data.*` dependencies.

**For each rule explains:**
- What resource type and attribute it checks
- What condition triggers a deny/warn
- What the developer sees when it fires
- Any allow-list or exception conditions

```
/platform-skills:opa explain
deny contains msg if {
    some name
    bucket := input.resource.aws_s3_bucket[name]
    bucket.acl == "public-read"
    msg := sprintf("S3 bucket '%s' must not be public", [name])
}
```
```
/platform-skills:opa explain ./policies/deny_unencrypted_s3.rego
```

---

### Mode: `debug`

Diagnoses why a policy is not firing (or firing when it shouldn't). Checks in order: namespace mismatch → rule name → input shape → partial vs set comprehension → `import rego.v1` missing → `some` missing.

```
/platform-skills:opa debug my deny rule produces no output when I run conftest test against main.tf
```
```
/platform-skills:opa debug — I have a warn rule that fires on everything, even compliant resources
```
```
/platform-skills:opa debug — conftest test passes with exit 0 but I expected a failure — [paste policy and input]
```

---

## `/platform-skills:kyverno`

**What it does:** Generate, test, audit, debug, and migrate Kyverno policies using the new CEL-based policy types (`ValidatingPolicy`, `MutatingPolicy`, `GeneratingPolicy`, `ImageValidatingPolicy` — all `apiVersion: policies.kyverno.io/v1`). Covers `matchConstraints`, `matchConditions`, CEL validations/mutations, `generator.Apply()`, Audit→Deny promotion, PolicyException, PolicyReport analysis, and migration from legacy `ClusterPolicy` or PodSecurityPolicy.

```
/platform-skills:kyverno [generate|test|audit|debug|migrate] [policy description or file path]
```

---

### Mode: `generate`

Writes a production-ready Kyverno policy using the new CEL-based types. Always starts in `validationActions: [Audit]` unless Deny is explicitly requested.

**What gets generated:**
- `apiVersion: policies.kyverno.io/v1` with the appropriate kind (`ValidatingPolicy`, `MutatingPolicy`, `GeneratingPolicy`, or `ImageValidatingPolicy`)
- `annotations` block: `policies.kyverno.io/title`, `category`, `severity`, `description`
- `matchConstraints.resourceRules` targeting only the required kinds and operations
- `matchConditions` with CEL to exclude system namespaces — replaces the old `exclude` block
- For `ValidatingPolicy`: `validations[].expression` (CEL boolean); `messageExpression` for dynamic messages
- For `MutatingPolicy`: `mutations[].patchType: ApplyConfiguration` with `Object{...}` CEL for merges; `patchType: JSONPatch` with `[JSONPatch{...}]` CEL for precise path operations
- For `GeneratingPolicy`: `variables` with `dyn()` for inline resources; `generate[].expression` using `generator.Apply(namespace, [resources])`; `evaluation.synchronize.enabled: true`
- For `ImageValidatingPolicy`: `matchImageReferences`; `attestors` with Cosign keyless or key-based; `validations` using `verifyImageSignatures()` CEL function
- kyverno-cli command to dry-run: `kyverno apply <policy.yaml> --resource <manifest.yaml> --detailed-results`

```
/platform-skills:kyverno generate a ValidatingPolicy that requires all Deployments to have app.kubernetes.io/team and app.kubernetes.io/name labels
```
```
/platform-skills:kyverno generate a ValidatingPolicy that denies privileged containers in all namespaces except kube-system
```
```
/platform-skills:kyverno generate a GeneratingPolicy that creates a default-deny-ingress NetworkPolicy in every new namespace
```
```
/platform-skills:kyverno generate an ImageValidatingPolicy that requires all images to be signed with Cosign keyless (Sigstore)
```

---

### Mode: `test`

Writes a `kyverno-test.yaml` manifest and resource fixture files to verify a policy with the kyverno CLI.

**Structure generated:**
- A **passing resource** (result: pass) for each validation
- A **failing resource** (result: fail) for each validation
- A **skipped resource** (result: skip) if `matchConditions` exclude a namespace
- `kyverno-test.yaml` referencing all resources with expected results
- Command: `kyverno test .`

```
/platform-skills:kyverno test — [paste ValidatingPolicy YAML] — write the test manifest and resource fixtures
```
```
/platform-skills:kyverno test write tests for my disallow-privileged-containers ValidatingPolicy
```

---

### Mode: `audit`

Reads PolicyReport data from a running cluster and produces a ranked, actionable violation summary.

**What it does:**
1. Queries `kubectl get policyreport -A` and `kubectl get clusterpolicyreport` for all failures
2. Groups violations by policy (highest severity first), then by resource kind
3. Assesses each violation: fixable in the manifest, or needs a PolicyException?
4. Shows the `kubectl patch` command to promote each zero-violation policy from Audit to Deny: `kubectl patch validatingpolicy <name> --type merge -p '{"spec":{"validationActions":["Deny"]}}'`
5. Flags Deny-mode policies with active violations — indicates a suppressed PolicyException needs review

```
/platform-skills:kyverno audit — here is my policyreport output: [paste JSON or describe violations]
```
```
/platform-skills:kyverno audit we're ready to move require-labels to Deny, what violations remain?
```

---

### Mode: `debug`

Diagnoses why a Kyverno policy is not behaving as expected.

**Checks in order:**
1. Webhook not registered (`kubectl get validatingwebhookconfigurations`)
2. `matchConstraints.resourceRules` not covering the resource kind, apiGroup, or operation
3. `matchConditions` CEL expression filtering out the resource unexpectedly
4. `validationActions: [Audit]` — policy reports violations but does not block; check PolicyReport, not admission events
5. `evaluation.background.enabled: false` — existing resources never evaluated
6. CEL expression syntax error (check `kubectl describe` events on the resource)
7. PolicyException silently suppressing a violation

```
/platform-skills:kyverno debug my ValidatingPolicy is in Audit mode but policyreport shows no violations for existing Deployments
```
```
/platform-skills:kyverno debug my CEL expression blocks every Pod even when it should pass — [paste ValidatingPolicy YAML]
```
```
/platform-skills:kyverno debug CEL evaluation error on admission — [paste policy and the admission event]
```

---

### Mode: `migrate`

Guides migration from legacy `ClusterPolicy` (`kyverno.io/v1`) or PodSecurityPolicy to the new CEL-based types.

**From legacy ClusterPolicy:**

| Legacy field | New equivalent |
|---|---|
| `spec.rules[].match.any[].resources` | `spec.matchConstraints.resourceRules[]` |
| `spec.rules[].exclude` | `spec.matchConditions` with CEL negation |
| `validate.pattern` (JMESPath anchors) | `validations[].expression` (CEL boolean) |
| `validate.deny.conditions` | `validations[].expression` with inverted CEL |
| `mutate.patchStrategicMerge` | `mutations[].patchType: ApplyConfiguration` with `Object{...}` |
| `mutate.patchesJSON6902` | `mutations[].patchType: JSONPatch` with `[JSONPatch{...}]` |
| `generate.data` / `generate.clone` | `generate[].expression` using `generator.Apply()` and `resource.Get()` |
| `validationFailureAction: Enforce` | `validationActions: [Deny]` |
| `validationFailureAction: Audit` | `validationActions: [Audit]` |

**From PodSecurityPolicy:**
- Maps each PSP field to a `ValidatingPolicy` CEL expression
- Deploys all policies in `[Audit]` mode first
- Fixes workloads, creates PolicyExceptions for legitimate carve-outs
- Removes PSPs only after all equivalents are in `[Deny]` with zero violations

**From OPA/Gatekeeper:**
- Translates ConstraintTemplate Rego logic to `ValidatingPolicy` CEL expressions
- Maps `input.review.object` → `object`, `deny` rule → `validations[].expression` with inverted logic
- Runs Gatekeeper and Kyverno policies in parallel for violation-count comparison before decommissioning

```
/platform-skills:kyverno migrate I'm migrating from PSP — here are my existing PodSecurityPolicies: [paste YAML]
```
```
/platform-skills:kyverno migrate translate this legacy ClusterPolicy to the new ValidatingPolicy type: [paste YAML]
```
```
/platform-skills:kyverno migrate translate this Gatekeeper ConstraintTemplate to a Kyverno ValidatingPolicy: [paste YAML]
```

---

## `/platform-skills:compliance`

**What it does:** SOC 2 compliance for Terraform infrastructure. Gap analysis, control implementation, audit evidence collection, Checkov remediation — all mapped to Trust Services Criteria (TSC).

```
/platform-skills:compliance [topic: gap | control | evidence | remediate | checklist]
```

---

### Mode: `gap`

Maps your Terraform config or description to SOC 2 TSC criteria, identifies gaps, and prioritises: Critical (audit blocker) / High (likely finding) / Medium (improvement).

**Output format:**
```
Criterion  | Finding                           | Severity  | Fix
CC6.7      | S3 bucket missing KMS CMK         | Critical  | Add aws_s3_bucket_server_side_encryption_configuration
CC7.2      | CloudTrail not multi-region       | Critical  | Set is_multi_region_trail = true
CC6.6      | Security group allows 0.0.0.0/0   | High      | Restrict to VPN CIDR
```

```
/platform-skills:compliance gap analyze my EKS Terraform module for SOC 2 CC6.1 access control gaps
```
```
/platform-skills:compliance gap we're going through a SOC 2 Type II audit in 3 months — run a gap analysis on our AWS infrastructure config
```

---

### Mode: `control`

Implements a specific SOC 2 control in Terraform. States the criterion, provides the exact resource(s), lists the Checkov rule IDs, and shows the auditor evidence command.

```
/platform-skills:compliance control implement CC6.7 encryption at rest for our RDS instances
```
```
/platform-skills:compliance control CC7.2 — how do I implement CloudTrail with integrity validation and multi-region coverage?
```

---

### Mode: `evidence`

Provides copy-paste AWS CLI commands to gather audit evidence for a specific criterion. Notes what each output proves and flags any elevated permissions required.

```
/platform-skills:compliance evidence CC6.7 — what AWS CLI commands do I run to show auditors that all S3 buckets have encryption enabled?
```
```
/platform-skills:compliance evidence CC6.6 — how do I prove to auditors that no security groups allow 0.0.0.0/0 on port 22?
```

---

### Mode: `remediate`

Fixes a specific Checkov or audit finding. Provides: criterion mapping, root cause, exact old → new Terraform block, blast radius (will this replace the resource?), validation steps, rollback.

```
/platform-skills:compliance remediate CKV_AWS_18: S3 bucket does not have access logging enabled
```
```
/platform-skills:compliance remediate CKV_AWS_86: CloudFront distribution does not have logging enabled
```

---

### Mode: `checklist`

Runs through the full SOC 2 readiness checklist. For each item: pass / fail / unknown. For fails and unknowns: what's needed + which Checkov rule enforces it. Ends with a prioritised action list.

```
/platform-skills:compliance checklist — we have Terraform for EKS, RDS, S3, IAM, and CloudTrail
```

---

## `/platform-skills:datadog`

**What it does:** End-to-end Datadog coverage — Agent deployment on Kubernetes, APM instrumentation, monitors, dashboards, SLOs, live incident investigation via the Datadog MCP server, pup CLI operations, and LLM Observability instrumentation and evaluation.

```
/platform-skills:datadog [setup|instrument|monitor|dashboard|slo|investigate|debug|pup|llmo] [service or description]
```

---

### Mode: `setup`

Deploys the Datadog Agent on Kubernetes via Helm. Asks for: Kubernetes distribution (EKS/AKS/GKE), Datadog site (EU `datadoghq.eu` / US `datadoghq.com`), features needed.

**Generates:** Helm values with API key from Kubernetes Secret (never hardcoded), APM enabled, log collection enabled, cluster name set, Cluster Agent with 2 replicas. Adds Unified Service Tagging (`DD_ENV`, `DD_SERVICE`, `DD_VERSION`) to app Deployment.

```
/platform-skills:datadog setup EKS cluster, EU site, need APM and log collection
```
```
/platform-skills:datadog setup how do I add Unified Service Tagging to my existing Deployments?
```

---

### Mode: `instrument`

Adds APM tracing to a service. Asks for: language and framework, whether log-trace correlation is needed.

- **Node.js**: `dd-trace` init as the **first** import
- **Python**: `ddtrace-run` entry point or `patch_all()` + `DD_TRACE_ENABLED`
- Adds custom spans for business-critical paths
- Shows expected APM UI outcome: service map entry, latency/error rate populated

```
/platform-skills:datadog instrument Node.js Express orders service — need log-trace correlation
```
```
/platform-skills:datadog instrument Python FastAPI payments service — add custom spans for the payment processing flow
```

---

### Mode: `monitor`

Generates a Terraform `datadog_monitor` resource. Sets `notify_no_data: true`, warning and critical thresholds, PagerDuty/Slack notification handles, and `service:`, `env:`, `team:` tags for routing.

```
/platform-skills:datadog monitor high error rate on orders-service — critical at 5%, warning at 2%, notify @pagerduty-platform @slack-alerts
```
```
/platform-skills:datadog monitor p99 latency for the checkout service — critical over 1s, warning over 500ms
```

---

### Mode: `dashboard`

Generates a Terraform `datadog_dashboard` with RED method widgets using APM metrics. Template variables for `env` and `service`.

```
/platform-skills:datadog dashboard orders-service RED dashboard — request rate, error rate, p50/p95/p99 latency
```

---

### Mode: `slo`

Generates a Terraform `datadog_service_level_objective`. Links to monitors for error budget burn alerts.

```
/platform-skills:datadog slo orders-service availability SLO — 99.9% target, 30-day window, warn at 99.95%
```

---

### Mode: `investigate`

**Live incident investigation using the Datadog MCP server.** Requires the MCP server connected — see `references/datadog.md` → MCP Server Setup.

Runs a 4-phase investigation through the MCP:

| Phase | What gets queried |
|-------|-----------------|
| 1. Triage | Active monitors in ALERT/WARN, event stream last 30 min, recent deployments |
| 2. Signals | Error logs for the incident window, APM error rate + p99 time series, sample failing traces |
| 3. Root cause | Before/after metric comparison, endpoint-level error breakdown, host CPU/memory |
| 4. Resolution | Acknowledge/resolve monitor, post incident Slack update, create post-mortem notebook |

```
/platform-skills:datadog investigate orders-service error rate spiked at 14:30 UTC — still ongoing
```

Natural language queries Claude sends to the MCP:
```
What monitors are firing for service:orders-service env:production right now?
Show error logs for orders-service between 14:30 and 15:00 UTC.
Compare the error rate before and after 14:30 UTC.
Which endpoints have the highest error rate?
```

---

### Mode: `debug`

Diagnoses Datadog data gaps without the MCP server. Classifies: Agent unhealthy, APM missing, logs not ingested, Monitor in No Data, custom metric not visible.

```
/platform-skills:datadog debug APM traces are missing for the payments-service — agent shows healthy
```
```
/platform-skills:datadog debug monitor is stuck in "No Data" — the service is definitely running
```

---

### `pup` mode

Scripted Datadog operations via the `pup` CLI — log search, metric queries, monitor management, and post-deploy quality gates.

```
/platform-skills:datadog pup search error logs for orders-service in the last 30 minutes
/platform-skills:datadog pup query p99 latency for orders-service over the last hour
/platform-skills:datadog pup mute the high error rate monitor for orders-service for 1 hour
/platform-skills:datadog pup generate a post-deploy gate script that fails CI if error rate exceeds 5%
```

### `llmo` mode

Instrument an AI application with Datadog LLM Observability, bootstrap evaluators, or root-cause LLM failures.

```
/platform-skills:datadog llmo instrument my Python OpenAI app with LLMObs — I need faithfulness scoring
/platform-skills:datadog llmo add evaluation scores to my Node.js LLM spans and set up a CI quality gate
/platform-skills:datadog llmo root-cause this failing trace — trace ID 8f3a2b1c9d4e5f6a
/platform-skills:datadog llmo compare gpt-4o vs gpt-4o-mini on my orders-assistant over the last 7 days
```

---

## `/platform-skills:dynatrace`

**What it does:** Dynatrace Operator deployment, OneAgent injection, code-level instrumentation, custom metrics, SLOs, dashboards, anomaly detection, Davis AI, and live incident investigation via the Dynatrace MCP server.

```
/platform-skills:dynatrace [setup|instrument|monitor|slo|dashboard|investigate|debug] [service or description]
```

---

### Mode: `setup`

Deploys the Dynatrace Operator and OneAgent on Kubernetes. Asks for: environment ID, Kubernetes distribution, monitoring mode.

- Uses `cloudNativeFullStack` for automatic injection — no pod restarts required
- Creates Kubernetes Secret with `apiToken` and `dataIngestToken` — never plain values
- Enables `metadataEnrichment: true` for k8s metadata on all telemetry

**Required token scopes:**
- `apiToken`: ReadConfig, WriteConfig, DataExport, LogExport, ReadSyntheticData, WriteAnomalyDetection
- `dataIngestToken`: metrics.ingest, logs.ingest

```
/platform-skills:dynatrace setup EKS cluster, environment ID abc12345, cloudNativeFullStack injection
```

---

### Mode: `instrument`

Adds custom spans for business logic (OneAgent auto-instruments HTTP/DB/cache/messaging). Asks for: language, operations to trace.

- **Node.js**: `@dynatrace/oneagent-sdk`
- **Python**: `oneagent-sdk`
- **Java**: OneAgent Java SDK
- Cross-service propagation via `x-dynatrace` header

```
/platform-skills:dynatrace instrument Node.js — add custom spans for the payment processing and order creation flows
```

---

### Mode: `monitor`

Generates Terraform `dynatrace_service_anomalies_v2` for failure rate and response time, plus `dynatrace_alerting` profile linked to PagerDuty/Slack/Opsgenie.

```
/platform-skills:dynatrace monitor orders-service — auto-detect anomalies, alert to PagerDuty platform-oncall
```

---

### Mode: `slo`

Generates Terraform `dynatrace_slo_v2`. Uses built-in availability metrics: `builtin:service.errors.server.successCount` / `builtin:service.requestCount.server`.

```
/platform-skills:dynatrace slo orders-service availability — 99.9% target, 30-day timeframe, warn at 99.5%
```

---

### Mode: `dashboard`

Generates Terraform `dynatrace_json_dashboard` with `DATA_EXPLORER` tiles for key service metrics.

```
/platform-skills:dynatrace dashboard orders-service — request count, response time, error rate, availability
```

---

### Mode: `investigate`

**Live incident investigation using the Dynatrace MCP server.** Requires the MCP server connected — see `references/dynatrace.md` → MCP Server Setup.

> **Cost note**: `execute_dql` queries scan Grail data and may incur costs. Start with short timeframes (1h–24h). Set `DT_GRAIL_QUERY_BUDGET_GB` to cap session spend.

Runs a 4-phase investigation:

| Phase | What gets queried |
|-------|-----------------|
| 1. Triage | Open Davis AI Problems, root cause entity and affected services, k8s events |
| 2. Signals | Error logs via DQL, exceptions with stack traces, distributed traces with errors |
| 3. Root cause (Davis AI) | Davis Copilot plain-English explanation, Davis Analyzer automated root cause |
| 4. Resolution | Create Dynatrace Notebook, send Slack/email, close Problem with resolution note |

Example DQL queries the MCP runs:
```dql
fetch logs
| filter service.name == "orders-service" and loglevel == "ERROR"
| sort timestamp desc
| limit 50
| fields timestamp, content, trace_id, span_id
```

```
/platform-skills:dynatrace investigate orders-service has an open Davis AI Problem since 14:00 UTC
```

---

### Mode: `debug`

Diagnoses data gaps without the MCP server. Classifies: injection failure, traces broken, custom metrics missing, SLO showing 0%, Davis AI not firing Problems.

```
/platform-skills:dynatrace debug OneAgent not injecting into pods in the checkout namespace
```
```
/platform-skills:dynatrace debug custom metrics not showing in Metrics Explorer — ingest endpoint returns 202
```

---

## `/platform-skills:document`

**What it does:** Generate or improve technical documentation — docstrings, OpenAPI 3.1 specs, documentation sites, and getting started guides.

```
/platform-skills:document [docstrings|openapi|site|guide] [language/framework] [path or description]
```

---

### Mode: `docstrings`

Adds or improves inline documentation. Asks for: language and preferred style.

| Language | Style options |
|----------|-------------|
| Python | Google, NumPy, Sphinx |
| TypeScript/JavaScript | JSDoc |

For each undocumented public function/class: purpose, all parameters with types, return value, exceptions raised, at least one example. Validates examples run (`python -m doctest`, `tsc --noEmit`). Generates coverage report (`interrogate`, `typedoc-coverage`).

**Does NOT document:** obvious getters/setters, private methods without complex invariants.

```
/platform-skills:document docstrings python Google-style — add docstrings to all public functions in src/auth/
```
```
/platform-skills:document docstrings typescript JSDoc — document the OrderService class and all public methods
```

---

### Mode: `openapi`

Generates or improves an OpenAPI 3.1 spec. Asks for: framework and existing routes or codebase.

**What gets generated:**
- All endpoints mapped: method, path, request body, response schemas per status code
- Shared schemas extracted to `components/schemas`
- Shared responses (400, 401, 404, 500) extracted to `components/responses`
- `operationId` on every operation
- Security scheme declared and applied globally or per-operation
- Validated with `npx @redocly/cli lint`

Framework-specific patterns:
- **FastAPI**: Pydantic `Field(description=...)` + route docstrings → auto-generates `/docs`
- **NestJS**: `@ApiProperty`, `@ApiOperation`, `@ApiResponse` decorators

```
/platform-skills:document openapi generate a spec for our Orders REST API — POST /orders, GET /orders/{id}, GET /orders with pagination
```
```
/platform-skills:document openapi FastAPI — generate OpenAPI spec from the existing route functions in app/routes/
```

---

### Mode: `site`

Sets up a documentation site for a project.

| Project type | Recommended generator |
|-------------|----------------------|
| Python library | MkDocs + mkdocstrings + Material theme |
| TypeScript SDK | TypeDoc + typedoc-material-theme |
| API portal | Redocly or Stoplight |
| General docs | Docusaurus |

Generates site config, nav structure (Getting Started, API Reference, Guides, Changelog), docstring auto-generation from source, search plugin, serve and build commands.

```
/platform-skills:document site Python library — set up MkDocs with auto-generated API reference from docstrings
```
```
/platform-skills:document site REST API portal — we want rendered API docs with try-it-out for partners
```

---

### Mode: `guide`

Writes a getting started guide or tutorial. Structure enforced:

1. **Prerequisites** — exact versions, accounts, permissions
2. **Installation** — copy-paste commands
3. **Quick start** — simplest working example (under 10 lines)
4. **Next steps** — links to deeper topics

Rules: all code examples tested and runnable, realistic values (not `<YOUR_VALUE>` placeholders), one concept per section, expected output for each command.

```
/platform-skills:document guide write a getting started guide for the orders-service SDK — Node.js, installing from npm, making the first API call
```
```
/platform-skills:document guide Kubernetes deployment guide for new engineers — assumes basic kubectl, no Helm knowledge
```

---

## `/platform-skills:mcp`

**What it does:** Scaffold, review, or debug Model Context Protocol (MCP) server implementations in TypeScript or Python.

```
/platform-skills:mcp [create|review|debug] [typescript|python] [description]
```

---

### Mode: `create`

Scaffolds a production-ready MCP server. Asks for: language, transport (stdio / HTTP+SSE), list of tools and resources needed.

**What gets generated:**
- Project scaffold with correct SDK setup (TypeScript SDK or Python `mcp` package)
- Tool handlers with Zod (TypeScript) or Pydantic (Python) schema validation — no `z.any()` or empty schemas
- Resource providers and prompt templates
- Transport configuration
- Error handling: `isError: true` content on failures, no unhandled exceptions
- Authentication and rate limiting for HTTP transports
- MCP Inspector test commands and expected responses
- Deployment checklist (env vars, secrets, logging)

```
/platform-skills:mcp create typescript — MCP server that exposes Kubernetes pod logs and events as tools, uses stdio transport
```
```
/platform-skills:mcp create python — MCP server that wraps our internal deployment API — 3 tools: list_services, get_status, trigger_deploy
```

---

### Mode: `review`

Reviews an existing MCP server or client. Evaluates in priority order:

1. **Protocol compliance** — JSON-RPC 2.0, capability negotiation, well-formed content arrays
2. **Schema validation** — Zod/Pydantic on all inputs, no `z.any()`
3. **Security** — no credentials in tool responses, auth on HTTP transports, rate limiting
4. **Error handling** — `isError: true` with message, no unhandled exceptions
5. **Transport** — correct transport for use case, no blocking sync code in async transports

```
/platform-skills:mcp review my MCP server — focus on whether error handling is correct and if the schemas are tight enough
```

---

### Mode: `debug`

Diagnoses protocol and integration failures. Classifies: Transport → Protocol → Schema → Handler → Integration.

**Evidence to collect:**
```bash
# Verify protocol compliance
npx @modelcontextprotocol/inspector node dist/index.js

# Smoke-test via stdio
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | node dist/index.js
```

```
/platform-skills:mcp debug tool is not appearing in the tools list in Claude — server starts without errors
```
```
/platform-skills:mcp debug tool call returns empty result but no error — the handler is executing
```
```
/platform-skills:mcp debug schema validation rejecting a valid input — Zod error: "Expected string, received number"
```

---

## `/platform-skills:product`

**What it does:** Platform product thinking — DevEx audits, friction analysis, RFC/ADR drafting, incident communication, blameless post-mortems, capacity planning, cost optimisation, and platform health review.

```
/platform-skills:product [topic: devex | friction | rfc | adr | incident | postmortem | capacity | cost | review]
```

Every response ends with: **Next step** (one concrete action to take immediately) + **Signal to watch** (one metric or observable that confirms the change is working).

---

### `devex`

Audits developer experience using the SPACE framework (Satisfaction, Performance, Activity, Communication, Efficiency). Identifies the top friction point from description, proposes one systemic fix (not a local patch), and suggests one metric to track improvement.

```
/platform-skills:product devex developers are spending 45 minutes to get a new service to production on day 1
```
```
/platform-skills:product devex CI pipeline takes 25 minutes — engineers skip it and push directly to staging
```

---

### `friction`

Maps the problem to the friction audit table (onboarding / CI / secrets / environment / ownership). States root cause, proposes the platform-level response, defines measurable "done".

```
/platform-skills:product friction every team has their own Terraform repo with different patterns — no shared modules
```
```
/platform-skills:product friction rotating secrets takes 3 engineers and an incident window
```

---

### `rfc`

Produces a complete RFC:
- Problem (what is broken, why now)
- Proposal (concrete change)
- Alternatives considered
- Impact (which teams, what migration)
- Open questions

```
/platform-skills:product rfc draft an RFC for migrating from Argo CD to Flux CD — 15 teams affected, GitOps repo restructure required
```
```
/platform-skills:product rfc adopt Gateway API as the standard ingress interface across all clusters
```

---

### `adr`

Produces a complete Architecture Decision Record:
- Context (what forced this decision)
- Decision (what was decided)
- Consequences (what becomes easier / harder / what to monitor)

```
/platform-skills:product adr decision to use Crossplane instead of Terraform for cluster-level infrastructure
```
```
/platform-skills:product adr we decided to use a mono-repo GitOps structure over per-team repos
```

---

### `incident`

Produces a structured incident status update:
- Time, severity, affected component
- Impact statement (user-visible, quantified if possible)
- What we know / what we are doing
- Next update time

```
/platform-skills:product incident orders-service is returning 500s, started at 14:30 UTC, about 20% of requests affected
```

---

### `postmortem`

Produces a blameless post-mortem structure:
- Timeline with timestamps
- Impact: duration, affected users, business impact
- Root cause: systemic, not human blame
- Contributing factors
- Action items with owner and due date

```
/platform-skills:product postmortem database failover at 02:15 UTC caused 18 minutes of downtime for checkout — root cause was missing health check on standby
```

---

### `capacity`

Ties growth to a business metric, states current baseline and projected growth, recommends headroom target and trigger threshold, proposes next review date.

```
/platform-skills:product capacity orders-service — currently 500 RPS at 60% CPU on 8 pods, expecting 3× growth in Q3
```

---

### `cost`

Identifies top cost driver, applies the monthly cost loop (rightsizing → unused resources → showback), proposes a specific reduction action with owner and deadline.

```
/platform-skills:product cost EC2 spend is $40k/month — largest cluster has m5.2xlarge nodes at 15% average CPU
```
```
/platform-skills:product cost we have 200 EBS volumes and no visibility into which are orphaned
```

---

### `review`

Runs the full platform health checklist covering Developer Experience, Operations, Security and Compliance, and Cost. Flags gaps and proposes the minimum action to close each.

```
/platform-skills:product review we're a 3-team platform org, 12 clusters, planning a SOC 2 audit in 6 months
```

---

## `/platform-skills:pr-review`

Comprehensive pre-merge risk review across six dimensions. Each mode inspects the diff and current file state, reports findings with severity, and recommends concrete fixes.

**Modes**

| Mode | What it reviews |
|---|---|
| `cost` | Compute, storage, and network spend delta |
| `drift` | Environment alignment across dev/staging/prod overlays and values files |
| `ownership` | CODEOWNERS gaps, missing team labels, Terraform module README, PR governance |
| `compliance` | SOC 2 control impact — IAM, encryption, logging, network, change management |
| `upgrade` | Deprecated Kubernetes APIs, loose Terraform provider constraints, floating action versions, `:latest` images |
| `rollback` | Reversibility and blast radius score for every change |
| `full` | All six modes in sequence with a Merge Readiness Summary |

**Usage**

```
/platform-skills:pr-review cost [paste gh pr diff output or PR number]
/platform-skills:pr-review drift
/platform-skills:pr-review ownership
/platform-skills:pr-review compliance
/platform-skills:pr-review upgrade
/platform-skills:pr-review rollback
/platform-skills:pr-review full 42
```

**Example prompts**

```
/platform-skills:pr-review cost — here is the diff for PR #42: [paste output of gh pr diff 42]
```
```
/platform-skills:pr-review drift — values-dev.yaml changed, check if prod is aligned
```
```
/platform-skills:pr-review compliance — new IAM role added, verify CC6.1 and CC6.2
```
```
/platform-skills:pr-review rollback — we're renaming a Deployment and adding an RDS storage increase
```
```
/platform-skills:pr-review full 42
```

**Multi-mode workflow**

```
/platform-skills:pr-review full   # get the complete risk picture
# fix blockers
/platform-skills:review           # validate specific manifests before re-review
```

Reference: `references/pr-review.md`

---

## `/platform-skills:triage`

Triage a PR review or issue comment from a bot, CI tool, or human reviewer. The command fetches the comment and diff with `gh`, classifies the thread, applies a minimal fix when the feedback is valid, replies, and resolves the review thread.

**Modes**

| Mode | What it does |
|---|---|
| `<PR number> <comment ID>` | Triage one specific comment |
| `--all <PR number>` | Triage every unresolved review thread on the PR |

**Usage**

```
/platform-skills:triage 42 123456789
/platform-skills:triage --all 42
```

**Classifications**

| Classification | Meaning |
|---|---|
| `ACTIONABLE_FIX` | Real issue in the changed files; apply the minimal fix, reply, and resolve |
| `INFORMATIONAL` | Question or non-blocking suggestion; answer, reply, and resolve |
| `NOT_APPLICABLE` | Status message, duplicate, already fixed, or outside this PR; explain and resolve |

Reference: `commands/triage.md` and `examples/triage/README.md`

---

## `/platform-skills:keda`

Design, generate, debug, and review KEDA (Kubernetes Event-Driven Autoscaling) ScaledObject and ScaledJob resources.

**Modes**

| Mode | What it does |
|---|---|
| `generate` | Write a production-ready ScaledObject or ScaledJob from a description |
| `debug` | Diagnose why a ScaledObject is not scaling as expected |
| `review` | Correctness, security, and operational safety review |
| `scale` | Design a scaling strategy for a workload from requirements |

**Usage**

```
/platform-skills:keda generate
/platform-skills:keda generate SQS queue, scale-to-zero, IRSA auth, max 20 replicas
/platform-skills:keda generate cron schedule weekday 08:00-20:00 Europe/Berlin, safety-net Prometheus trigger
/platform-skills:keda debug
/platform-skills:keda review
[paste ScaledObject YAML]
/platform-skills:keda scale
```

**Generate examples**

```
/platform-skills:keda generate
```
*Generates a ScaledObject for the orders-processor Deployment using SQS. Uses IRSA (no static credentials), scale-to-zero, activationQueueLength to prevent flapping, and HPA stabilization.*

```
/platform-skills:keda generate cron schedule checkout-api 08:00-20:00 Europe/Berlin
```
*Generates a ScaledObject with weekday/weekend Cron windows plus a Prometheus safety-net trigger for unexpected spikes.*

```
/platform-skills:keda generate ScaledJob SQS batch one-job-per-message
```
*Generates a ScaledJob with `restartPolicy: Never`, `activeDeadlineSeconds`, and security hardening.*

**Debug checklist**

The debug mode works through this checklist in order:

1. Is the ScaledObject `Active: true`? — check `kubectl describe scaledobject`
2. Is the HPA showing `<unknown>` targets? — metrics adapter connection
3. Is `activationThreshold` / `activationQueueLength` too high?
4. Is `minReplicaCount: 1` preventing scale-to-zero?
5. Is a Cron trigger keeping a replica floor?
6. Has `cooldownPeriod` elapsed?
7. Is there an existing HPA conflict?

**Key rules enforced**

- Never inline credentials in ScaledObject — always `TriggerAuthentication`
- Prefer IRSA over static access keys
- Never create your own HPA for a KEDA-managed Deployment
- Always set `timezone` explicitly on Cron triggers
- Never overlap Cron windows
- Set `restoreToOriginalReplicaCount: true`

Reference: `commands/keda.md`, `references/keda.md`, and `examples/keda/`

---

## `/platform-skills:self-improve`

**What it does:** Bootstrap and operate a self-improving agent workspace. Creates and maintains `.learnings/` directories, logs LRN/ERR/FEAT entries, reviews accumulated patterns, and promotes recurring learnings to project memory.

**Works on:** Any project workspace. Most useful when working with an AI assistant over multiple sessions to accumulate reusable patterns, catch recurring errors, and evolve agent behavior.

```
/platform-skills:self-improve [init|log|review|promote] [description or file path]
```

| Mode | What it does |
|------|--------------|
| `init` | Scaffold `.learnings/` directory with `LEARNINGS.md`, `ERRORS.md`, `FEATURE_REQUESTS.md`, and `memory/working-buffer.md` |
| `log` | Append a new LRN, ERR, or FEAT entry to the appropriate file based on the description |
| `review` | Scan `.learnings/` for recurring patterns (threshold: 3+ occurrences) and surface candidates for promotion |
| `promote` | Promote a recurring pattern from `.learnings/` into `CLAUDE.md` or project memory |

**Example usage:**

```
/platform-skills:self-improve init
```
*Creates the full `.learnings/` scaffold in the current workspace.*

```
/platform-skills:self-improve log ERR helm upgrade failed due to immutable selectorLabels
```
*Appends an ERR entry with timestamp, context, and resolution to `.learnings/ERRORS.md`.*

```
/platform-skills:self-improve review
```
*Scans all `.learnings/` files, identifies patterns appearing 3+ times, and returns promotion candidates ranked by VFM score.*

```
/platform-skills:self-improve promote "never include app.kubernetes.io/version in selectorLabels"
```
*Appends the pattern to `CLAUDE.md` memory and marks the source entry as promoted.*

**Key rules enforced**

- Entry format: `[YYYY-MM-DD] [ID] [TAG] description` with `Context:`, `Resolution:`, `Frequency:` fields
- Promotion threshold: 3+ occurrences or single high-severity ERR
- WAL protocol: append-only `.learnings/` files; never edit existing entries
- VFM scoring: Velocity × Frequency × Magnitude determines promotion priority
- ADL protocol: decide Adopt / Defer / Reject for each promotion candidate

Reference: `commands/self-improve.md`, `references/agent-self-improve.md`, and `examples/agent-self-improve/`

---

## `/platform-skills:supply-chain`

Secure the software supply chain from build pipeline to running container.

**Modes**

| Mode | What it does |
|---|---|
| `audit` | Review an existing pipeline for supply chain security gaps |
| `sign` | Walk through Cosign keyless signing setup (Sigstore/Rekor, no key management) |
| `sbom` | Generate and attest an SBOM with Syft |
| `scan` | Trivy or Grype CVE scan with configurable severity gate |
| `enforce` | Generate Kyverno `ImageValidatingPolicy` to block unsigned images at admission |
| `slsa` | SLSA Level 2 provenance via `slsa-github-generator` GitHub Actions reusable workflow |

**Usage**

```
/platform-skills:supply-chain audit
/platform-skills:supply-chain sign
/platform-skills:supply-chain sbom
/platform-skills:supply-chain scan
/platform-skills:supply-chain enforce
/platform-skills:supply-chain slsa
[paste workflow YAML or describe your registry/CI setup]
```

**Key rules enforced**

- Never store signing keys in CI — use keyless (OIDC + Rekor) only
- Always sign the digest (`@sha256:…`), never the tag
- Pin all action versions to SHA, not tag
- Gate on CRITICAL+HIGH by default; document exceptions
- Deploy Kyverno `ImageValidatingPolicy` in Audit mode first, then Deny

Reference: `references/supply-chain.md` and `examples/supply-chain/`

---

## `/platform-skills:runtime-security`

Detect and respond to in-container threats at the syscall level using Falco.

**Modes**

| Mode | What it does |
|---|---|
| `install` | Deploy Falco on EKS/GKE with eBPF driver via Helm |
| `rules` | Write and unit-test custom Falco rules |
| `alerts` | Configure Falcosidekick to route alerts to Slack, PagerDuty, or webhook |
| `debug` | Diagnose why a Falco rule is not firing |
| `harden` | Map Falco alert metadata to Kyverno admission enforcement |

**Usage**

```
/platform-skills:runtime-security install
/platform-skills:runtime-security rules
[describe the threat you want to detect]
/platform-skills:runtime-security alerts
/platform-skills:runtime-security debug
[paste kubectl logs output from Falco pod]
/platform-skills:runtime-security harden
```

**Key rules enforced**

- Always use eBPF driver on managed Kubernetes — never kernel module
- Never run Falco as a sidecar — must be a DaemonSet
- Do not set CPU limits on Falco DaemonSet — event processing is bursty
- Set `minimumpriority: warning` for Slack routing; suppress DEBUG/INFO noise
- Test every custom rule with `falco-event-generator` before production

Reference: `references/runtime-security.md` and `examples/runtime-security/`

---

## `/platform-skills:chaos`

Litmus Chaos and Chaos Mesh fault injection, steady-state hypothesis, GameDay workflow, and DORA feedback loop.

**Modes:**

| Mode | What it does |
|---|---|
| `install` | Helm install for Litmus Chaos or Chaos Mesh with namespace isolation and RBAC |
| `experiment` | Generate a fault experiment (ChaosEngine or Chaos Mesh CRD) from a description |
| `schedule` | Wrap an experiment in a recurring schedule (ChaosSchedule or Chaos Mesh Schedule CRD) |
| `gameday` | Structured GameDay runbook: steady-state → blast radius → inject → observe → verdict → DORA impact |
| `debug` | Diagnose failed or stuck experiments — ChaosResult, chaos-runner logs, RBAC gaps |
| `report` | Summarize blast radius, steady-state probe timeline, recovery time, and DORA delta |

**Usage:**

```
/platform-skills:chaos install [litmus|chaos-mesh] [namespace]
/platform-skills:chaos experiment [fault-class] [target-workload]
/platform-skills:chaos schedule [experiment-name] [interval]
/platform-skills:chaos gameday
/platform-skills:chaos debug [experiment-name]
/platform-skills:chaos report [experiment-name]
```

**Examples:**

```
/platform-skills:chaos install litmus
/platform-skills:chaos experiment pod-delete my-service
/platform-skills:chaos schedule pod-delete weekly
/platform-skills:chaos gameday
/platform-skills:chaos debug pod-delete-engine
/platform-skills:chaos report pod-delete-engine
```

Reference: `references/chaos.md` and `examples/chaos/`

---

## `/platform-skills:dora`

GitHub Actions + Prometheus instrumentation for all four DORA metrics — Deployment Frequency, Lead Time for Changes, Change Failure Rate, and MTTR.

**Modes:**

| Mode | What it does |
|---|---|
| `instrument` | Generate GitHub Actions steps to push deploy and incident events to Prometheus Pushgateway |
| `dashboard` | Generate a Grafana dashboard with four DORA panels and Elite/High/Medium/Low threshold bands |
| `benchmark` | Classify current metric values against 2023 DORA performance bands; identify weakest metric |
| `debug` | Diagnose missing deployment events, missing MTTR, CFR stuck at 0%, or metrics stopping at a date |

**Usage:**

```
/platform-skills:dora instrument [workflow-file]
/platform-skills:dora dashboard
/platform-skills:dora benchmark [metric-values]
/platform-skills:dora debug [metric-name]
```

**Examples:**

```
/platform-skills:dora instrument .github/workflows/deploy.yml
/platform-skills:dora dashboard
/platform-skills:dora benchmark "deploy_freq=2, lead_time=3600, cfr=8, mttr=7200"
/platform-skills:dora debug mttr
```

Reference: `references/dora.md` and `examples/dora/`

---

---

## `/platform-skills:awesome-docs`

Generate, convert, and maintain animated GitHub-safe Markdown documents with animated SVG diagrams.

**Usage:** `/platform-skills:awesome-docs <mode> [topic or file path]`

### Mode: `generate`

Create a full animated doc from scratch. The skill runs a guided interview — topic, components, flow direction — then generates SVGs one at a time with visual confirmation before the next.

```
/platform-skills:awesome-docs generate KEDA autoscaling
/platform-skills:awesome-docs generate Falco runtime security
/platform-skills:awesome-docs generate --theme docs-light Linkerd service mesh
```

### Mode: `convert`

Inject animated SVGs into an existing plain Markdown doc.

```
/platform-skills:awesome-docs convert docs/keda-guide.md
/platform-skills:awesome-docs convert README.md
```

### Mode: `update`

Revise a single diagram in an existing doc.

```
/platform-skills:awesome-docs update assets/keda-arch-flow.svg
/platform-skills:awesome-docs update "Architecture section"
```

### Mode: `diff`

Detect stale diagrams vs `git HEAD`.

```
/platform-skills:awesome-docs diff KEDA-DEMO.md
```

### Mode: `audit`

Quality check — missing captions, broken refs, env-specific IDs, missing diagrams.

```
/platform-skills:awesome-docs audit KEDA-DEMO.md
```

### Mode: `preview`

Open the doc locally in a browser before committing.

```
/platform-skills:awesome-docs preview KEDA-DEMO.md
```

### Mode: `export`

Generate animated HTML for Confluence/Notion, or get PNG export instructions.

```
/platform-skills:awesome-docs export KEDA-DEMO.md html
/platform-skills:awesome-docs export KEDA-DEMO.md png
```

Reference: `references/awesome-docs.md` and `examples/awesome-docs/`

---

## Tips for best results

**Paste context** — paste the manifest, error output, plan output, or code block directly after the command. The more concrete the input, the more actionable the output.

**You don't need the slash command** — describe your problem in plain English and the skill activates automatically when you're working with relevant files.

**Chain commands** — `/platform-skills:debug` to diagnose, then `/platform-skills:review` to validate the fix before merging.

**Multi-mode workflows:**
- New service: `instrument` → `alert` → `dashboard` → `loadtest`
- New policy: `generate` → `test` → `validate`
- New Helm chart: `create` → `review` → `security`
- Incident: `investigate` → `postmortem` → `rfc` (if systemic)
- Compliance: `gap` → `remediate` → `evidence` → `checklist`

**Deep-dive references** — each command points to a `references/<domain>.md` file. Read those for full spec coverage, edge cases, and worked examples.
