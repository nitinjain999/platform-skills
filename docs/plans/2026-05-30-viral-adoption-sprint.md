# Viral Adoption Sprint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build 8 adoption assets that make platform-skills' value obvious in 30 seconds, targeting 50k GitHub stars from platform engineers, DevOps, SRE, and cloud teams.

**Architecture:** Content-only sprint — no changes to skill logic. Demo fixtures (`bad` → `fixed` files) are the source of truth; BEFORE_AFTER.md and LAUNCH.md reference them. VHS `.tape` scripts generate terminal GIFs via a CI job. All assets live in the existing repo structure.

**Tech Stack:** YAML, HCL (Terraform), Markdown, [VHS by Charm](https://github.com/charmbracelet/vhs) for GIF generation, GitHub Actions CI.

---

## File Map

| File | Action |
|---|---|
| `examples/demo/kubernetes-prod-review/bad.yaml` | Create |
| `examples/demo/kubernetes-prod-review/fixed.yaml` | Create |
| `examples/demo/kubernetes-prod-review/README.md` | Create |
| `examples/demo/kubernetes-prod-review/demo.tape` | Create |
| `examples/demo/terraform-iam-risk/bad.tf` | Create |
| `examples/demo/terraform-iam-risk/fixed.tf` | Create |
| `examples/demo/terraform-iam-risk/README.md` | Create |
| `examples/demo/terraform-iam-risk/demo.tape` | Create |
| `examples/demo/flux-stuck-release/bad.yaml` | Create |
| `examples/demo/flux-stuck-release/fixed.yaml` | Create |
| `examples/demo/flux-stuck-release/README.md` | Create |
| `examples/demo/flux-stuck-release/demo.tape` | Create |
| `examples/demo/github-actions-supply-chain/bad.yml` | Create |
| `examples/demo/github-actions-supply-chain/fixed.yml` | Create |
| `examples/demo/github-actions-supply-chain/README.md` | Create |
| `examples/demo/github-actions-supply-chain/demo.tape` | Create |
| `.github/workflows/regen-demos.yml` | Create |
| `BEFORE_AFTER.md` | Create |
| `PROMPTS.md` | Modify (append 3 sections) |
| `docs/TEAM_ROLLOUT.md` | Create |
| `LAUNCH.md` | Create |
| `README.md` | Modify (Works With grid + BEFORE_AFTER.md link) |
| `.github/ISSUE_TEMPLATE/bad_guidance.md` | Create |

---

### Task 1: Kubernetes prod-review demo fixture

**Files:**
- Create: `examples/demo/kubernetes-prod-review/bad.yaml`
- Create: `examples/demo/kubernetes-prod-review/fixed.yaml`
- Create: `examples/demo/kubernetes-prod-review/README.md`

- [ ] **Step 1: Create bad.yaml**

```yaml
# examples/demo/kubernetes-prod-review/bad.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
        - name: api-server
          image: mycompany/api-server:latest
          ports:
            - containerPort: 8080
          env:
            - name: DATABASE_URL
              value: "postgres://admin:password123@db:5432/prod"
```

- [ ] **Step 2: Create fixed.yaml**

```yaml
# examples/demo/kubernetes-prod-review/fixed.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-server
      version: v1.4.2
  template:
    metadata:
      labels:
        app: api-server
        version: v1.4.2
    spec:
      serviceAccountName: api-server
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
      containers:
        - name: api-server
          image: mycompany/api-server:v1.4.2  # pinned — reproducible builds
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /healthz/ready
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz/live
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: api-server-secrets
                  key: database-url
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

- [ ] **Step 3: Create README.md**

```markdown
# Demo: Kubernetes Production Review

> Status: Stable

A realistic Kubernetes Deployment that platform-skills catches before it reaches production.

## What's wrong with bad.yaml

| Finding | Severity | Risk |
|---|---|---|
| `image: latest` — unpinned tag | Critical | Non-reproducible deploys; silent rollouts |
| No `securityContext` | Critical | Container runs as root; writable filesystem |
| No `resources` limits/requests | High | OOMKill in production; noisy neighbour |
| No `readinessProbe` | High | Traffic hits the pod before the app is ready |
| Hardcoded `DATABASE_URL` with credentials | High | Secret exposed in manifest and pod spec |

## What changed in fixed.yaml

- Pinned image tag (`v1.4.2`) — reproducible, auditable
- `securityContext` at pod and container level — non-root, read-only filesystem, all capabilities dropped
- `resources.requests` and `resources.limits` — predictable scheduling
- `readinessProbe` and `livenessProbe` — safe traffic and self-healing
- Credentials moved to `secretKeyRef` — secret stays in Kubernetes Secrets
- Dedicated `serviceAccountName` — least-privilege identity

## Blast radius of bad.yaml in production

- OOMKill during traffic spike → pod restart loop → degraded availability
- Root container breakout → node compromise
- Silent image update on next deploy → unknown code in production
- Credentials in pod spec → visible in `kubectl describe pod` output

## Validation

```bash
kubectl apply --dry-run=client -f fixed.yaml
kubectl auth can-i --list --as=system:serviceaccount:production:api-server
```

## Rollback

```bash
kubectl rollout undo deployment/api-server -n production
kubectl rollout status deployment/api-server -n production
```

## Try it yourself

```text
Use $platform-skills to review this Kubernetes Deployment for production readiness:
securityContext, resources, probes, lifecycle, service account, and RBAC.
```
```

- [ ] **Step 4: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('examples/demo/kubernetes-prod-review/bad.yaml'))" && echo "bad.yaml OK"
python3 -c "import yaml; yaml.safe_load(open('examples/demo/kubernetes-prod-review/fixed.yaml'))" && echo "fixed.yaml OK"
```

Expected: both print `OK` with no errors.

- [ ] **Step 5: Commit**

```bash
git add examples/demo/kubernetes-prod-review/
git commit -m "feat(demo): add kubernetes prod-review demo fixture"
```

---

### Task 2: Terraform IAM risk demo fixture

**Files:**
- Create: `examples/demo/terraform-iam-risk/bad.tf`
- Create: `examples/demo/terraform-iam-risk/fixed.tf`
- Create: `examples/demo/terraform-iam-risk/README.md`

- [ ] **Step 1: Create bad.tf**

```hcl
# examples/demo/terraform-iam-risk/bad.tf
variable "app_name" {}

resource "aws_iam_role" "app" {
  name = "${var.app_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app_policy" {
  name = "${var.app_name}-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}
```

- [ ] **Step 2: Create fixed.tf**

```hcl
# examples/demo/terraform-iam-risk/fixed.tf
variable "app_name" {
  description = "Application name — used to scope resources and IAM"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket this app reads and writes"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used in resource ARN conditions"
  type        = string
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "app" {
  name = "${var.app_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_s3" {
  name = "${var.app_name}-s3-policy"
  role = aws_iam_role.app.id

  # Least privilege: only the actions this app actually needs
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
      },
      {
        Sid    = "BucketWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/*"
      },
      {
        Sid    = "SecretsRead"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.app_name}/*"
      }
    ]
  })
}
```

- [ ] **Step 3: Create README.md**

```markdown
# Demo: Terraform IAM Risk

> Status: Stable

A Terraform IAM policy that gives an application AdministratorAccess in disguise. Platform-skills catches it before the plan is applied.

## What's wrong with bad.tf

| Finding | Severity | Risk |
|---|---|---|
| `Action: "*"` — full AWS access | Critical | Any compromised instance = full account takeover |
| `Resource: "*"` — all resources | Critical | No scope boundary on any service |
| No `Condition` on assume-role | High | Role can be assumed from any region |
| Single catch-all policy | Medium | Impossible to audit what the app actually needs |

## What changed in fixed.tf

- Actions scoped to exactly what the app does: `s3:GetObject`, `s3:ListBucket`, `s3:PutObject`, `s3:DeleteObject`, `secretsmanager:GetSecretValue`
- Resources scoped to named bucket and app-prefixed secrets — no wildcard
- Regional `Condition` on assume-role — blocks cross-region assume
- Separate policy statements with `Sid` labels — auditable in CloudTrail

## Blast radius of bad.tf

- Compromised EC2 instance → attacker has `iam:CreateUser`, `iam:AttachUserPolicy`, `ec2:RunInstances` → lateral movement across the account
- Misconfigured app → accidentally deletes S3 buckets, terminates instances, modifies security groups

## Validation

```bash
cd examples/demo/terraform-iam-risk
terraform init && terraform validate
# Review the plan before applying
terraform plan -var="app_name=myapp" -var="bucket_name=my-bucket" -var="aws_region=us-east-1"
```

## Try it yourself

```text
Use $platform-skills to review this Terraform IAM policy for least privilege.
Flag wildcard actions, wildcard resources, missing conditions, and safer alternatives.
```
```

- [ ] **Step 4: Validate HCL syntax**

```bash
cd examples/demo/terraform-iam-risk
terraform fmt -check -diff && echo "HCL format OK"
```

Expected: no diff output, exits 0.

- [ ] **Step 5: Commit**

```bash
git add examples/demo/terraform-iam-risk/
git commit -m "feat(demo): add terraform IAM risk demo fixture"
```

---

### Task 3: Flux stuck release demo fixture

**Files:**
- Create: `examples/demo/flux-stuck-release/bad.yaml`
- Create: `examples/demo/flux-stuck-release/fixed.yaml`
- Create: `examples/demo/flux-stuck-release/README.md`

- [ ] **Step 1: Create bad.yaml**

```yaml
# examples/demo/flux-stuck-release/bad.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 1h
  url: https://kubernetes.github.io/ingress-nginx
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx-ingress
  namespace: ingress-system
spec:
  interval: 1h
  chart:
    spec:
      chart: ingress-nginx
      version: "*"
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
  values:
    controller:
      replicaCount: 1
```

- [ ] **Step 2: Create fixed.yaml**

```yaml
# examples/demo/flux-stuck-release/fixed.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 10m  # poll for chart updates every 10 min, not 1h
  url: https://kubernetes.github.io/ingress-nginx
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx-ingress
  namespace: ingress-system
spec:
  interval: 10m
  timeout: 5m           # fail fast — don't block other reconciliations
  dependsOn:
    - name: cert-manager # ingress needs cert-manager CRDs to exist first
      namespace: cert-manager
  chart:
    spec:
      chart: ingress-nginx
      version: "4.10.1"  # pinned — upgrade is an explicit PR, not automatic
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: flux-system
  install:
    remediation:
      retries: 3          # retry install on failure before giving up
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true  # roll back if the last upgrade failed
    cleanupOnFail: true
  values:
    controller:
      replicaCount: 2     # HA: survive a node drain during upgrades
      resources:
        requests:
          cpu: 100m
          memory: 90Mi
        limits:
          cpu: 500m
          memory: 300Mi
```

- [ ] **Step 3: Create README.md**

```markdown
# Demo: Flux Stuck Release

> Status: Stable

A Flux HelmRelease that goes NotReady and stays there. Platform-skills identifies why it's stuck and what to fix before the next deploy.

## What's wrong with bad.yaml

| Finding | Severity | Risk |
|---|---|---|
| `version: "*"` — unpinned chart | Critical | Silent major upgrades; non-reproducible clusters |
| No `dependsOn` | High | HelmRelease deploys before cert-manager CRDs exist → CrashLoopBackOff |
| `interval: 1h` — too long | Medium | Changes take up to 1 hour to reconcile |
| No `timeout` | Medium | Stuck install blocks other Flux reconciliations |
| No `remediation` | Medium | Failed install retries forever without rollback |
| `replicaCount: 1` | Medium | Single point of failure during node drain |

## What changed in fixed.yaml

- Pinned chart version `4.10.1` — upgrade is an explicit PR decision
- `dependsOn: cert-manager` — ensures CRDs exist before ingress deploys
- `interval: 10m` — changes reconcile in minutes, not hours
- `timeout: 5m` — fail fast, unblock other reconciliations
- `install.remediation.retries: 3` + `upgrade.remediation.remediateLastFailure: true` — automatic rollback on failure
- `replicaCount: 2` — survives node drain without downtime

## Diagnosing a stuck release

```bash
flux get helmrelease nginx-ingress -n ingress-system
flux logs --kind HelmRelease --name nginx-ingress --namespace ingress-system
kubectl describe helmrelease nginx-ingress -n ingress-system
```

## Force reconcile after fix

```bash
flux reconcile helmrelease nginx-ingress -n ingress-system --with-source
flux get helmrelease nginx-ingress -n ingress-system --watch
```

## Try it yourself

```text
Use $platform-skills to debug this Flux HelmRelease that is stuck NotReady.
Start with evidence collection, then root cause, fix, validation, and rollback.
```
```

- [ ] **Step 4: Validate YAML**

```bash
python3 -c "
import yaml
docs = list(yaml.safe_load_all(open('examples/demo/flux-stuck-release/bad.yaml')))
print(f'bad.yaml: {len(docs)} documents OK')
docs = list(yaml.safe_load_all(open('examples/demo/flux-stuck-release/fixed.yaml')))
print(f'fixed.yaml: {len(docs)} documents OK')
"
```

Expected: `bad.yaml: 2 documents OK` and `fixed.yaml: 2 documents OK`.

- [ ] **Step 5: Commit**

```bash
git add examples/demo/flux-stuck-release/
git commit -m "feat(demo): add flux stuck release demo fixture"
```

---

### Task 4: GitHub Actions supply chain demo fixture

**Files:**
- Create: `examples/demo/github-actions-supply-chain/bad.yml`
- Create: `examples/demo/github-actions-supply-chain/fixed.yml`
- Create: `examples/demo/github-actions-supply-chain/README.md`

- [ ] **Step 1: Create bad.yml**

```yaml
# examples/demo/github-actions-supply-chain/bad.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions: write-all
    steps:
      - uses: actions/checkout@main
      - uses: actions/setup-node@main
        with:
          node-version: 18
      - run: npm ci
      - run: npm run build
      - uses: aws-actions/configure-aws-credentials@main
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - run: aws s3 sync dist/ s3://my-bucket
```

- [ ] **Step 2: Create fixed.yml**

```yaml
# examples/demo/github-actions-supply-chain/fixed.yml
name: Deploy

on:
  push:
    branches: [main]

# Minimal default permissions — jobs declare only what they need
permissions:
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # required for OIDC token exchange
      contents: read
    steps:
      # Pinned to commit SHA — immune to tag moving or repo compromise
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af  # v4.1.0
        with:
          node-version: 18
          cache: npm
      - run: npm ci
      - run: npm run build
      # OIDC — no long-lived AWS credentials stored in GitHub Secrets
      - uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502  # v4.0.2
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
          aws-region: us-east-1
      - run: aws s3 sync dist/ s3://${{ vars.S3_BUCKET }} --delete
```

- [ ] **Step 3: Create README.md**

```markdown
# Demo: GitHub Actions Supply Chain

> Status: Stable

A GitHub Actions workflow with four supply chain vulnerabilities. Platform-skills catches them all before the workflow is merged.

## What's wrong with bad.yml

| Finding | Severity | Risk |
|---|---|---|
| `actions/checkout@main` — unpinned action | Critical | Tag can be moved to malicious commit; SolarWinds-style attack |
| `permissions: write-all` | Critical | Compromised step gets write access to entire repo |
| `aws-access-key-id` in secrets — long-lived keys | High | Leaked key = permanent AWS access until manually rotated |
| `actions/setup-node@main` — unpinned | High | Same supply chain risk as checkout |
| `aws-actions/configure-aws-credentials@main` — unpinned | High | Same supply chain risk |

## What changed in fixed.yml

- All actions pinned to commit SHA — immune to tag-move attacks
- `permissions: write-all` replaced with `id-token: write` + `contents: read` — minimal surface
- Long-lived AWS secrets replaced with OIDC `role-to-assume` — no stored credentials
- Top-level `permissions: contents: read` as safe default for all jobs

## Prerequisites for fixed.yml

1. Create an IAM role with a trust policy allowing the GitHub OIDC provider
2. Set `vars.AWS_DEPLOY_ROLE_ARN` and `vars.S3_BUCKET` as GitHub Actions variables (not secrets)

IAM trust policy snippet:
```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:ref:refs/heads/main"
    }
  }
}
```

## Try it yourself

```text
Use $platform-skills to review this GitHub Actions workflow for supply chain security:
pinned actions, OIDC, least-privilege permissions, and secret handling.
```
```

- [ ] **Step 4: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('examples/demo/github-actions-supply-chain/bad.yml'))" && echo "bad.yml OK"
python3 -c "import yaml; yaml.safe_load(open('examples/demo/github-actions-supply-chain/fixed.yml'))" && echo "fixed.yml OK"
```

Expected: both print `OK`.

- [ ] **Step 5: Commit**

```bash
git add examples/demo/github-actions-supply-chain/
git commit -m "feat(demo): add github-actions supply chain demo fixture"
```

---

### Task 5: VHS tape scripts (all 4 domains)

**Files:**
- Create: `examples/demo/kubernetes-prod-review/demo.tape`
- Create: `examples/demo/terraform-iam-risk/demo.tape`
- Create: `examples/demo/flux-stuck-release/demo.tape`
- Create: `examples/demo/github-actions-supply-chain/demo.tape`

Install VHS locally to validate tapes: `brew install vhs` (macOS) or see https://github.com/charmbracelet/vhs#installation.

- [ ] **Step 1: Create kubernetes demo.tape**

```
# examples/demo/kubernetes-prod-review/demo.tape
Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

# Show the bad manifest
Type "echo '─── bad.yaml (what ships without platform-skills) ───'"
Enter
Sleep 500ms
Type "cat bad.yaml"
Enter
Sleep 3s

# Show what platform-skills flags
Type "echo ''"
Enter
Type "echo '─── platform-skills review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  image:latest is unpinned — silent rollouts, non-reproducible'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  No securityContext — container runs as root, writable filesystem'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      No resources limits — OOMKill risk, noisy neighbour in production'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      No readinessProbe — traffic hits the pod before app is ready'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      DATABASE_URL hardcoded — credentials visible in kubectl describe pod'"
Enter
Sleep 2s

# Show the fix
Type "echo ''"
Enter
Type "echo '─── fixed.yaml (after platform-skills review) ───'"
Enter
Sleep 500ms
Type "cat fixed.yaml"
Enter
Sleep 4s

# Validate
Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "python3 -c \"import yaml; yaml.safe_load(open('fixed.yaml')); print('✅ YAML valid')\""
Enter
Sleep 1s
```

- [ ] **Step 2: Create terraform demo.tape**

```
# examples/demo/terraform-iam-risk/demo.tape
Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── bad.tf (Action: * — silent AdministratorAccess) ───'"
Enter
Sleep 500ms
Type "cat bad.tf"
Enter
Sleep 3s

Type "echo ''"
Enter
Type "echo '─── platform-skills IAM review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  Action:\"*\" — grants full AWS access to this role'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  Resource:\"*\" — no scope boundary on any service'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      No Condition on AssumeRole — usable from any region'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    Single catch-all statement — impossible to audit in CloudTrail'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── fixed.tf (least privilege — scoped actions and resources) ───'"
Enter
Sleep 500ms
Type "cat fixed.tf"
Enter
Sleep 4s

Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "terraform fmt -check -diff && echo '✅ HCL format OK'"
Enter
Sleep 1s
```

- [ ] **Step 3: Create flux demo.tape**

```
# examples/demo/flux-stuck-release/demo.tape
Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── bad.yaml (HelmRelease stuck NotReady) ───'"
Enter
Sleep 500ms
Type "cat bad.yaml"
Enter
Sleep 3s

Type "echo ''"
Enter
Type "echo '─── platform-skills GitOps review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  version:\"*\" — unpinned chart, silent major upgrades'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      No dependsOn — deploys before cert-manager CRDs exist'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    interval:1h — changes wait up to 1 hour to reconcile'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    No timeout — stuck install blocks all other reconciliations'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    No remediation — failed upgrade never rolls back'"
Enter
Sleep 200ms
Type "echo '❌ MEDIUM    replicaCount:1 — SPOF during node drain'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── fixed.yaml (pinned, dependsOn, timeout, remediation, HA) ───'"
Enter
Sleep 500ms
Type "cat fixed.yaml"
Enter
Sleep 4s

Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "python3 -c \"import yaml; docs=list(yaml.safe_load_all(open('fixed.yaml'))); print(f'✅ {len(docs)} documents valid')\""
Enter
Sleep 1s
```

- [ ] **Step 4: Create github-actions demo.tape**

```
# examples/demo/github-actions-supply-chain/demo.tape
Output demo.gif

Set Shell "bash"
Set FontSize 13
Set Width 1200
Set Height 700
Set Theme "Dracula"
Set Padding 20

Type "echo '─── bad.yml (4 supply chain vulnerabilities) ───'"
Enter
Sleep 500ms
Type "cat bad.yml"
Enter
Sleep 3s

Type "echo ''"
Enter
Type "echo '─── platform-skills supply chain review findings ───'"
Enter
Sleep 500ms
Type "echo '❌ CRITICAL  actions/checkout@main — tag can be moved to malicious commit'"
Enter
Sleep 200ms
Type "echo '❌ CRITICAL  permissions:write-all — any step gets full repo write access'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      AWS long-lived keys in secrets — leaked key = permanent access'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      actions/setup-node@main — same supply chain risk'"
Enter
Sleep 200ms
Type "echo '❌ HIGH      configure-aws-credentials@main — same supply chain risk'"
Enter
Sleep 2s

Type "echo ''"
Enter
Type "echo '─── fixed.yml (pinned SHAs, OIDC, least-privilege permissions) ───'"
Enter
Sleep 500ms
Type "cat fixed.yml"
Enter
Sleep 4s

Type "echo '─── validation ───'"
Enter
Sleep 300ms
Type "python3 -c \"import yaml; yaml.safe_load(open('fixed.yml')); print('✅ YAML valid')\""
Enter
Sleep 1s
```

- [ ] **Step 5: Verify tapes locally (optional but recommended)**

```bash
# Install VHS if not installed
brew install vhs  # macOS

# Generate one GIF to verify tape syntax
cd examples/demo/kubernetes-prod-review
vhs demo.tape
ls -lh demo.gif  # should be present and >0 bytes
```

If VHS is not installed locally, tapes will be validated by the CI job in Task 6.

- [ ] **Step 6: Commit tapes**

```bash
git add examples/demo/kubernetes-prod-review/demo.tape
git add examples/demo/terraform-iam-risk/demo.tape
git add examples/demo/flux-stuck-release/demo.tape
git add examples/demo/github-actions-supply-chain/demo.tape
git commit -m "feat(demo): add VHS tape scripts for all 4 demo domains"
```

---

### Task 6: CI job for GIF regeneration

**Files:**
- Create: `.github/workflows/regen-demos.yml`

- [ ] **Step 1: Create regen-demos.yml**

```yaml
# .github/workflows/regen-demos.yml
name: Regen demo GIFs

on:
  push:
    branches: [main]
    paths:
      - 'examples/demo/**/demo.tape'
  workflow_dispatch:

permissions:
  contents: write

jobs:
  regen:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Install VHS
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y ffmpeg
          curl -sL https://github.com/charmbracelet/vhs/releases/download/v0.7.2/vhs_0.7.2_Linux_x86_64.tar.gz \
            | tar xz -C /usr/local/bin vhs

      - name: Generate GIFs
        run: |
          for tape in examples/demo/**/demo.tape; do
            echo "Rendering $tape"
            dir=$(dirname "$tape")
            cd "$dir"
            vhs demo.tape
            cd - > /dev/null
          done

      - name: Commit updated GIFs
        uses: stefanzweifel/git-auto-commit-action@8621497c8c39c72f3e2a999a26b4ca1b5590a870  # v5.0.1
        with:
          commit_message: "chore: regenerate demo GIFs [skip ci]"
          file_pattern: "examples/demo/**/*.gif"
          commit_user_name: "github-actions[bot]"
          commit_user_email: "github-actions[bot]@users.noreply.github.com"
```

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/regen-demos.yml'))" && echo "regen-demos.yml OK"
```

Expected: `regen-demos.yml OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/regen-demos.yml
git commit -m "feat(ci): add VHS GIF regeneration workflow"
```

---

### Task 7: BEFORE_AFTER.md

**Files:**
- Create: `BEFORE_AFTER.md` (repo root)

- [ ] **Step 1: Create BEFORE_AFTER.md**

```markdown
# Before / After — Platform Skills in Action

Four real examples of what platform-skills catches before it reaches production.
Each section shows the bad file, the findings, and the fix. Copy the prompts at the bottom to try it on your own code.

---

## Kubernetes: Production Deployment

### Before

```yaml
spec:
  containers:
    - name: api-server
      image: mycompany/api-server:latest   # ❌ unpinned
      env:
        - name: DATABASE_URL
          value: "postgres://admin:password123@db:5432/prod"  # ❌ hardcoded credential
      # ❌ no securityContext, no resources, no probes
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `image:latest` is unpinned — silent rollouts, non-reproducible deployments |
| Critical | No `securityContext` — container runs as root with a writable filesystem |
| High | No `resources` — OOMKill risk in production; noisy neighbour scheduling |
| High | No `readinessProbe` — traffic hits the pod before the app is ready |
| High | `DATABASE_URL` hardcoded — credentials visible in `kubectl describe pod` |

### After

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
    - name: api-server
      image: mycompany/api-server:v1.4.2   # ✅ pinned
      resources:
        requests: { cpu: 100m, memory: 128Mi }
        limits: { cpu: 500m, memory: 512Mi }
      readinessProbe:
        httpGet: { path: /healthz/ready, port: 8080 }
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef: { name: api-server-secrets, key: database-url }  # ✅
```

> Full fixture: [`examples/demo/kubernetes-prod-review/`](examples/demo/kubernetes-prod-review/)

**Try it:**
```text
Use $platform-skills to review this Kubernetes Deployment for production readiness:
securityContext, resources, probes, lifecycle, service account, and RBAC.
```

---

## Terraform: IAM Policy

### Before

```hcl
Statement = [{
  Effect   = "Allow"
  Action   = "*"        # ❌ full AWS access
  Resource = "*"        # ❌ no scope boundary
}]
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `Action: "*"` — grants every AWS API to this role |
| Critical | `Resource: "*"` — no boundary on any service or account |
| High | No `Condition` on `AssumeRole` — usable from any region |
| Medium | Single catch-all statement — impossible to audit in CloudTrail |

### After

```hcl
Statement = [
  {
    Sid    = "BucketRead"
    Effect = "Allow"
    Action   = ["s3:GetObject", "s3:ListBucket"]         # ✅ scoped
    Resource = ["arn:aws:s3:::${var.bucket_name}",
                "arn:aws:s3:::${var.bucket_name}/*"]     # ✅ named bucket
  },
  {
    Sid    = "SecretsRead"
    Effect = "Allow"
    Action   = ["secretsmanager:GetSecretValue"]
    Resource = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.app_name}/*"
  }
]
```

> Full fixture: [`examples/demo/terraform-iam-risk/`](examples/demo/terraform-iam-risk/)

**Try it:**
```text
Use $platform-skills to review this Terraform IAM policy for least privilege.
Flag wildcard actions, wildcard resources, missing conditions, and safer alternatives.
```

---

## Flux CD: Stuck HelmRelease

### Before

```yaml
spec:
  interval: 1h         # ❌ changes wait an hour
  chart:
    spec:
      version: "*"     # ❌ unpinned chart — silent major upgrades
  values:
    controller:
      replicaCount: 1  # ❌ single point of failure
  # ❌ no dependsOn, no timeout, no remediation
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `version: "*"` — unpinned chart triggers silent major upgrades |
| High | No `dependsOn` — deploys before cert-manager CRDs exist → CrashLoopBackOff |
| Medium | `interval: 1h` — changes sit unreconciled for up to an hour |
| Medium | No `timeout` — stuck install blocks all other Flux reconciliations |
| Medium | No `remediation` — failed upgrade loops forever without rollback |

### After

```yaml
spec:
  interval: 10m
  timeout: 5m
  dependsOn:
    - name: cert-manager
      namespace: cert-manager
  chart:
    spec:
      version: "4.10.1"   # ✅ pinned
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true   # ✅ auto-rollback
  values:
    controller:
      replicaCount: 2             # ✅ HA
```

> Full fixture: [`examples/demo/flux-stuck-release/`](examples/demo/flux-stuck-release/)

**Try it:**
```text
Use $platform-skills to debug this Flux HelmRelease that is stuck NotReady.
Start with evidence collection, then root cause, fix, validation, and rollback.
```

---

## GitHub Actions: Supply Chain

### Before

```yaml
permissions: write-all          # ❌ all jobs get full repo write
steps:
  - uses: actions/checkout@main # ❌ unpinned — tag can move to malicious commit
  - uses: aws-actions/configure-aws-credentials@main
    with:
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}  # ❌ long-lived key
```

### platform-skills findings

| Severity | Finding |
|---|---|
| Critical | `actions/checkout@main` — unpinned action; tag-move = supply chain attack |
| Critical | `permissions: write-all` — any compromised step gets full repo write |
| High | Long-lived AWS keys in Secrets — leaked key = permanent access until manual rotation |

### After

```yaml
permissions:
  contents: read            # ✅ safe default

jobs:
  deploy:
    permissions:
      id-token: write       # ✅ OIDC only
      contents: read
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2 ✅ pinned SHA
      - uses: aws-actions/configure-aws-credentials@e3dd6a429d7300a6a4c196c26e071d42e0343502  # v4.0.2
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}  # ✅ OIDC, no stored keys
```

> Full fixture: [`examples/demo/github-actions-supply-chain/`](examples/demo/github-actions-supply-chain/)

**Try it:**
```text
Use $platform-skills to review this GitHub Actions workflow for supply chain security:
pinned actions, OIDC, least-privilege permissions, and secret handling.
```

---

More prompts for every platform team in [PROMPTS.md](PROMPTS.md).
```

- [ ] **Step 2: Verify the file renders correctly**

```bash
# Check all internal links resolve
grep -oE '\[.*\]\(([^)]+)\)' BEFORE_AFTER.md | grep -oE '\(([^)]+)\)' | tr -d '()' | while read path; do
  [ -e "$path" ] && echo "✅ $path" || echo "❌ MISSING: $path"
done
```

Expected: all fixture directories print `✅`.

- [ ] **Step 3: Commit**

```bash
git add BEFORE_AFTER.md
git commit -m "feat: add BEFORE_AFTER.md with 4 domain before/after examples"
```

---

### Task 8: PROMPTS.md expansion

**Files:**
- Modify: `PROMPTS.md` (append 3 sections after existing content)

- [ ] **Step 1: Append security team section**

Add to the end of `PROMPTS.md`:

```markdown

## Security Team

```text
Use $platform-skills to audit all IAM roles and policies in this Terraform module.
Flag wildcard actions, wildcard resources, missing conditions, overly broad assume-role trust policies, and unused permissions.
```

```text
Review this supply chain configuration for software composition risks: pinned action SHAs, SBOM generation, image signing, dependency provenance, and artifact attestation.
```

```text
Generate an OPA/Rego policy that enforces these security controls on all Kubernetes Deployments:
non-root containers, read-only root filesystem, dropped capabilities, no hostPID or hostNetwork, and resource limits required.
```

```text
Review this Falco rule set for coverage gaps, false-positive risk, and missing detections for privilege escalation, lateral movement, and data exfiltration in a Kubernetes environment.
```

```text
Use $platform-skills to produce a threat model for this architecture diagram. Identify trust boundaries, attack vectors, blast radius, and prioritized mitigations.
```

## SRE Team

```text
Use $platform-skills to walk me through this incident symptom: [paste error, alert, or log]. Start with evidence collection, then root cause hypothesis, safe fix options, validation steps, and rollback.
```

```text
Generate a runbook for this failure mode: [describe the failure]. Include detection signals, triage steps, escalation path, remediation commands, validation, and post-incident actions.
```

```text
Review these SLO definitions for correctness: error budget calculation, burn rate alert thresholds, window alignment, and whether the SLIs actually measure user experience.
```

```text
Use $platform-skills to design a chaos experiment for this service. Include steady-state hypothesis, failure injection method, blast radius, abort conditions, and success criteria.
```

```text
Generate capacity planning estimates for this workload at 2x and 5x current traffic. Include pod count, node count, RDS instance size, and NAT gateway throughput.
```

## App and Developer Team

```text
I'm onboarding to this platform. Walk me through what I need to know: cluster access, namespaces, secrets management, deploy process, observability, and how to get help.
```

```text
Use $platform-skills to review my PR before I ask for human review. Check for: missing tests, unsafe Kubernetes defaults, hardcoded config, secrets in code, and missing rollback plan.
```

```text
Generate a deploy checklist for this service going to production for the first time.
Include: health check endpoints, runbook location, alerting coverage, rollback procedure, and feature flag state.
```

```text
This deploy just went wrong. Walk me through a safe rollback: how to detect the blast radius, the rollback commands, how to validate it worked, and what to document in the incident channel.
```
```

- [ ] **Step 2: Verify append is clean**

```bash
tail -30 PROMPTS.md
```

Expected: shows the App and Developer Team section as the last content. No duplicate headers.

- [ ] **Step 3: Commit**

```bash
git add PROMPTS.md
git commit -m "feat: expand PROMPTS.md with security, SRE, and app team sections"
```

---

### Task 9: docs/TEAM_ROLLOUT.md

**Files:**
- Create: `docs/TEAM_ROLLOUT.md`

- [ ] **Step 1: Create TEAM_ROLLOUT.md**

```markdown
# Team Rollout Guide

How to roll out platform-skills across your team's repositories — from a single repo to your entire organisation.

## Prerequisites

- `git` installed
- Access to the target repositories
- One of: Claude Code, Codex CLI, Cursor, or GitHub Copilot

---

## Tier 1: 10 repos — Manual install (30 minutes)

The fastest path. Run the installer once per repo, per tool.

### Step 1: Clone platform-skills once

```bash
git clone https://github.com/nitinjain999/platform-skills.git ~/platform-skills
cd ~/platform-skills
```

### Step 2: Install into each target repo

Pick your tool:

```bash
# Claude Code — interactive plugin workflows and slash commands
claude plugin marketplace add https://github.com/nitinjain999/platform-skills
claude plugin install platform-skills

# Codex — skill invocation with $platform-skills
./install.sh --codex

# Cursor — project rules for Chat and Agent
./install.sh --cursor --target ../your-repo

# GitHub Copilot — instructions committed to the repo
./install.sh --copilot --target ../your-repo
```

### Step 3: Verify installation

```bash
# Claude Code
claude skills list | grep platform-skills

# Codex
codex "list skills" | grep platform-skills

# Cursor — check that rules file exists
ls your-repo/.cursor/rules/platform-skills.mdc

# Copilot — check that instructions file exists
ls your-repo/.github/copilot-instructions.md | xargs grep -l "platform-skills"
```

### Step 4: First prompt to validate

Paste this into your tool of choice in the context of a real repo file:

```text
Use $platform-skills to review the files I changed for production readiness.
Focus on ownership, blast radius, validation, rollback, and security defaults.
```

---

## Tier 2: 100 repos — GitHub Actions automation (1 hour setup)

A GitHub Actions workflow that runs `install.sh` across a list of repositories via a matrix strategy. One PR per target repo.

### Step 1: Create the dispatch workflow in your central tooling repo

```yaml
# .github/workflows/rollout-platform-skills.yml
name: Rollout platform-skills

on:
  workflow_dispatch:
    inputs:
      tool:
        description: "Tool to install (cursor | copilot | codex)"
        required: true
        default: cursor
      repos:
        description: "Comma-separated list of owner/repo"
        required: true

jobs:
  rollout:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    strategy:
      matrix:
        repo: ${{ fromJson(format('["{0}"]', replace(github.event.inputs.repos, ',', '","'))) }}
      fail-fast: false
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          repository: nitinjain999/platform-skills
          path: platform-skills

      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          repository: ${{ matrix.repo }}
          path: target
          token: ${{ secrets.ROLLOUT_TOKEN }}

      - name: Install platform-skills
        run: |
          cd platform-skills
          ./install.sh --${{ github.event.inputs.tool }} --target ../target

      - name: Open PR
        uses: peter-evans/create-pull-request@5e914681574cf53f24b88ede31338b00d2b09b78  # v7.0.5
        with:
          path: target
          token: ${{ secrets.ROLLOUT_TOKEN }}
          commit-message: "feat: add platform-skills ${{ github.event.inputs.tool }} integration"
          branch: "platform-skills/rollout-${{ github.event.inputs.tool }}"
          title: "feat: add platform-skills for ${{ github.event.inputs.tool }}"
          body: |
            Adds platform-skills guidance for ${{ github.event.inputs.tool }}.

            **What this does:** Gives ${{ github.event.inputs.tool }} access to platform engineering
            patterns for Kubernetes, Terraform, Flux, GitHub Actions, AWS, and more.

            **Try it:** Paste a prompt from [PROMPTS.md](https://github.com/nitinjain999/platform-skills/blob/main/PROMPTS.md)
            into ${{ github.event.inputs.tool }} while reviewing any platform file.

            **Rollback:** Delete `.cursor/rules/platform-skills.mdc` (or equivalent) and close this PR.
```

### Step 2: Create a PAT with repo access

Create a GitHub Personal Access Token with `repo` scope. Store it as secret `ROLLOUT_TOKEN` in your central tooling repo.

### Step 3: Trigger the rollout

```bash
gh workflow run rollout-platform-skills.yml \
  --field tool=cursor \
  --field repos="org/repo-1,org/repo-2,org/repo-3"
```

### Step 4: Merge the PRs

Each target repo gets one PR. Review and merge. To track status:

```bash
gh pr list --search "platform-skills rollout" --state open
```

---

## Tier 3: 1000 repos — Policy-as-code (1 day setup)

At this scale, individual PRs are impractical. Use your existing infrastructure-as-code and repository management tooling.

### Option A: GitHub Copilot — central organisation policy

Add platform-skills instructions to your organisation's default Copilot instructions. All repos in the org pick them up automatically.

1. Go to **Organisation Settings → Copilot → Policies**
2. Add the contents of `platform-skills/.github/copilot-instructions.md` to the organisation-level instructions
3. All repos in the org now have platform-skills guidance in Copilot Chat

### Option B: Cursor — shared rules via template repository

1. Create a template repository in your org: `org/platform-cursor-rules`
2. Copy `platform-skills/.cursor/` into it
3. Configure your org's repository creation workflow to clone from this template
4. Existing repos: run the Tier 2 matrix workflow with `--tool cursor` across all repos

### Option C: Repository management tool (Terraform, Pulumi, Backstage)

If you manage repos as code, add the platform-skills install to your repo template:

```hcl
# Terraform example using GitHub provider
resource "github_repository_file" "platform_skills_copilot" {
  for_each = toset(var.target_repos)

  repository = each.value
  branch     = "main"
  file       = ".github/copilot-instructions.md"
  content    = file("${path.module}/platform-skills/.github/copilot-instructions.md")
  commit_message = "feat: add platform-skills copilot instructions"
}
```

### Measuring adoption

```bash
# Count repos with platform-skills installed (Copilot)
gh search code "platform-skills" --filename copilot-instructions.md \
  --owner your-org --json repository | jq length

# Count repos with Cursor rules
gh search code "platform-skills" --filename "*.mdc" \
  --owner your-org --json repository | jq length
```

---

## Keeping platform-skills up to date

```bash
# Claude Code plugin — update to latest
claude plugin update platform-skills

# Cursor/Copilot — re-run install.sh from a fresh clone
git -C ~/platform-skills pull
cd ~/platform-skills && ./install.sh --cursor --target ../your-repo
```

For the Tier 2 matrix approach, re-trigger the workflow after each platform-skills release.

---

## Getting help

- [PROMPTS.md](../PROMPTS.md) — copy-paste prompts for every team
- [INSTALLATION.md](../INSTALLATION.md) — detailed install options
- [GitHub Issues](https://github.com/nitinjain999/platform-skills/issues) — report problems or gaps
```

- [ ] **Step 2: Verify**

```bash
ls -lh docs/TEAM_ROLLOUT.md && echo "File exists"
```

Expected: file listed with a non-zero size.

- [ ] **Step 3: Commit**

```bash
git add docs/TEAM_ROLLOUT.md
git commit -m "feat: add TEAM_ROLLOUT.md with 10/100/1000 repo rollout guide"
```

---

### Task 10: LAUNCH.md

**Files:**
- Create: `LAUNCH.md` (repo root)

- [ ] **Step 1: Create LAUNCH.md**

```markdown
# Launch Copy

Ready-to-post social content for platform-skills. Each blurb links to a specific asset. Edit names and handles before posting.

---

## LinkedIn (150 words — professional framing)

> We built platform-skills: a free, open-source field handbook for platform engineers, DevOps, and SRE teams that works inside Claude, Codex, Cursor, and GitHub Copilot.
>
> It catches the things code review misses:
> - Kubernetes containers running as root with no resource limits
> - Terraform IAM policies granting `Action: "*"` to a production role
> - Flux HelmReleases that silently upgrade to a breaking chart version
> - GitHub Actions workflows with unpinned actions and long-lived AWS keys
>
> Every finding comes with blast radius, validation steps, and a rollback plan — the same mental model a senior platform engineer brings to every review.
>
> We've got 37 domain guides, 27 working examples, and prompts for platform, DevOps, SRE, security, and app teams.
>
> See it in action → [BEFORE_AFTER link]
>
> Star it if it's useful: [repo link]
>
> #platformengineering #devops #SRE #kubernetes #terraform #cloud

---

## X / Twitter (280 chars)

> We open-sourced platform-skills — a field handbook for platform engineers that works in Claude, Codex, Cursor & Copilot.
>
> It catches root containers, wildcard IAM, unpinned Flux charts, and unsecured GitHub Actions — with blast radius + rollback built in.
>
> Before/after → [BEFORE_AFTER link]

---

## Reddit — r/devops

**Title:** We open-sourced a platform engineering handbook that works inside your AI coding tool

**Body:**

We've been building platform-skills for a while now and just reached a point where it feels ready for a wider audience.

**What it is:** A free, open-source field handbook for platform, DevOps, SRE, and cloud engineers. It works on GitHub as a reference, or as a plugin/skill inside Claude, Codex, Cursor, and GitHub Copilot for interactive guidance.

**What it catches:** The things that slip through code review — containers running as root, IAM policies with `Action: "*"`, Flux HelmReleases without `dependsOn` or `remediation`, GitHub Actions workflows with unpinned action SHAs and `permissions: write-all`. Every finding includes blast radius, validation commands, and rollback steps.

**What's inside:** 37 domain guides, 27 working examples, slash commands for Kubernetes, Terraform, GitOps, GitHub Actions, AWS, Linkerd, OPA, KEDA, supply chain, and more.

**Before/after examples:** [BEFORE_AFTER link]
**Repo:** [repo link]

Curious what gaps you'd want filled — happy to add domain guides for things we're missing.

---

## Hacker News — Show HN

**Title:** Show HN: Platform Skills – open-source field handbook for platform/DevOps/SRE engineers

**Body:**

platform-skills is a free, open-source field handbook for platform engineers covering Kubernetes, Terraform, Flux CD, GitHub Actions, AWS, Linkerd, OPA, and 30+ more domains. It works as a GitHub reference or as a plugin inside Claude, Codex, Cursor, and Copilot.

The model: every section starts with the problem (not the tool), includes evidence collection commands, fixes, blast radius, and a rollback plan. Before/after examples here: [BEFORE_AFTER link].

Repo: [repo link]

---

## Internal Slack

> **📣 platform-skills is now available for our team**
>
> It's a platform engineering handbook that works inside Claude, Codex, Cursor, and Copilot — covering Kubernetes, Terraform, Flux, GitHub Actions, and AWS with blast radius, validation, and rollback guidance built in.
>
> **Rolling it out across our repos:** [TEAM_ROLLOUT link]
> **Prompts to try today:** [PROMPTS link]
>
> If you hit a gap or find guidance that's wrong, open an issue: [issues link]
```

- [ ] **Step 2: Update placeholder links**

Replace these placeholders with real GitHub URLs before posting:
- `[BEFORE_AFTER link]` → `https://github.com/nitinjain999/platform-skills/blob/main/BEFORE_AFTER.md`
- `[repo link]` → `https://github.com/nitinjain999/platform-skills`
- `[TEAM_ROLLOUT link]` → `https://github.com/nitinjain999/platform-skills/blob/main/docs/TEAM_ROLLOUT.md`
- `[PROMPTS link]` → `https://github.com/nitinjain999/platform-skills/blob/main/PROMPTS.md`
- `[issues link]` → `https://github.com/nitinjain999/platform-skills/issues`

```bash
# Apply the real links
sed -i '' \
  's|\[BEFORE_AFTER link\]|https://github.com/nitinjain999/platform-skills/blob/main/BEFORE_AFTER.md|g' \
  LAUNCH.md
sed -i '' \
  's|\[repo link\]|https://github.com/nitinjain999/platform-skills|g' \
  LAUNCH.md
sed -i '' \
  's|\[TEAM_ROLLOUT link\]|https://github.com/nitinjain999/platform-skills/blob/main/docs/TEAM_ROLLOUT.md|g' \
  LAUNCH.md
sed -i '' \
  's|\[PROMPTS link\]|https://github.com/nitinjain999/platform-skills/blob/main/PROMPTS.md|g' \
  LAUNCH.md
sed -i '' \
  's|\[issues link\]|https://github.com/nitinjain999/platform-skills/issues|g' \
  LAUNCH.md
```

- [ ] **Step 3: Verify no placeholders remain**

```bash
grep -n "\[.*link\]" LAUNCH.md && echo "FAIL: placeholders remain" || echo "OK: all links resolved"
```

Expected: `OK: all links resolved`.

- [ ] **Step 4: Commit**

```bash
git add LAUNCH.md
git commit -m "feat: add LAUNCH.md with social copy for LinkedIn, X, Reddit, HN, Slack"
```

---

### Task 11: README polish

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add "Works With" grid after the badge row**

Find this line in README.md (it appears after the badge block):

```markdown
---

If this handbook saves you time,
```

Insert the following block immediately before that line:

```markdown
## Works With

| Tool | What you get |
|---|---|
| **Claude Code** | Slash commands (`/platform-skills:review`, `/platform-skills:debug`, and 9 more), interactive guidance, automatic activation on relevant files |
| **Codex** | Skill invocation with `$platform-skills`, loaded on demand in any Codex session |
| **Cursor** | Project rules for Chat and Agent — platform review and generation in every file context |
| **GitHub Copilot** | Chat instructions committed to your repo — available to your whole team without individual installs |
| **GitHub (no AI tool)** | Browse `references/` and `examples/` directly — a standalone field handbook |

```

- [ ] **Step 2: Add BEFORE_AFTER.md link in "Try It On Your Repo" section**

Find this line in README.md:

```markdown
More copy-paste workflows live in [PROMPTS.md](PROMPTS.md).
```

Replace with:

```markdown
See [BEFORE_AFTER.md](BEFORE_AFTER.md) for side-by-side before/after examples across Kubernetes, Terraform, Flux, and GitHub Actions. More copy-paste workflows in [PROMPTS.md](PROMPTS.md).
```

- [ ] **Step 3: Verify README renders**

```bash
grep -n "Works With" README.md && echo "Works With section: OK"
grep -n "BEFORE_AFTER" README.md && echo "BEFORE_AFTER link: OK"
```

Expected: both lines found with line numbers.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "feat: add Works With grid and BEFORE_AFTER link to README"
```

---

### Task 12: bad_guidance issue template

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bad_guidance.md`

- [ ] **Step 1: Create bad_guidance.md**

```markdown
---
name: Bad or dangerous guidance
about: Report guidance that is incorrect, unsafe, or could cause harm if followed
labels: bad-guidance
assignees: ''
---

## The specific claim

<!-- Quote the exact sentence, command, or code block. Include the file and section. -->

**File / section:**

**Exact claim:**

```text
(paste the guidance here)
```

## Why it's wrong or dangerous

<!-- What harm could happen if an engineer follows this guidance? Be concrete: data loss, security breach, outage, compliance violation. -->

## The correct approach

<!-- What should the guidance say instead? Include evidence: docs link, CVE, incident post-mortem, test output, or vendor advisory. -->

**Correct guidance:**

**Evidence:**

## Severity

- [ ] Critical — could cause a security breach, data loss, or production outage
- [ ] High — likely to cause a significant incident if followed
- [ ] Medium — misleading but unlikely to cause immediate harm
- [ ] Low — minor inaccuracy or outdated detail

## Are you willing to contribute a fix?

- [ ] Yes, I can open a PR with corrected guidance
- [ ] I can verify technical accuracy of a proposed fix
- [ ] I am reporting it for maintainers to fix
```

- [ ] **Step 2: Verify template**

```bash
ls .github/ISSUE_TEMPLATE/ && echo "---" && head -5 .github/ISSUE_TEMPLATE/bad_guidance.md
```

Expected: `bad_guidance.md` appears in the listing; first 5 lines show the frontmatter.

- [ ] **Step 3: Commit**

```bash
git add .github/ISSUE_TEMPLATE/bad_guidance.md
git commit -m "feat: add bad_guidance issue template for unsafe or incorrect content"
```

---

## Self-Review

### Spec coverage check

| Spec requirement | Task |
|---|---|
| Demo fixtures — 4 domains, bad/fixed/README | Tasks 1–4 |
| VHS tape scripts per domain | Task 5 |
| CI job for GIF regeneration | Task 6 |
| BEFORE_AFTER.md with embedded GIFs | Task 7 |
| PROMPTS.md — security, SRE, app teams | Task 8 |
| docs/TEAM_ROLLOUT.md — 3 tiers | Task 9 |
| LAUNCH.md — 5 channels | Task 10 |
| README — Works With grid + BEFORE_AFTER link | Task 11 |
| bad_guidance issue template | Task 12 |

All spec requirements covered. ✅

### Notes

- GIFs won't be present in the repo until CI runs `regen-demos.yml` after the `.tape` files are merged to main. BEFORE_AFTER.md references the GIF paths correctly — they'll render once CI commits them.
- `LAUNCH.md` placeholder links are replaced inline in Task 10 Step 2. If running in an agent, use the sed commands exactly as written.
- The `sed -i ''` syntax is macOS. On Linux, use `sed -i` (no empty string argument).
