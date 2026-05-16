# How AI Coding Agents Work — and How to Use Platform Skills

This document explains what is happening under the hood when you use Claude with a skill like `platform-skills`, and how to get the most out of it.

---

## What Is an AI Coding Agent?

An AI coding agent is a large language model with access to tools and context — not a script, not a search engine, not an autocomplete.

When you open Claude Code in your project and ask a question, the agent:

1. **Reads context** — your conversation, open files, error output, and any installed skills
2. **Reasons** — identifies the problem type, relevant domain, and best approach
3. **Acts** — reads files, runs commands, writes code, or calls external tools depending on permissions
4. **Responds** — gives a concrete answer grounded in what it observed, not generic advice

The key difference from a chatbot: a coding agent takes actions in your environment. It can read your actual Terraform files, run `helm lint`, check `kubectl` output, and produce a diff — not just describe what you should do.

---

## How Skills Work

A skill is a set of instructions and reference material that shapes how Claude behaves for a specific domain. Installing `platform-skills` does not change Claude's model — it gives Claude a richer context about platform engineering that it applies automatically.

### What Gets Loaded

When you install `platform-skills`, Claude gets access to:

| File | Purpose |
|------|---------|
| `skills/platform-skills/SKILL.md` | Core routing logic — which tool owns which concern, platform rules, how to structure answers |
| `references/*.md` | Deep-dive guides loaded on demand when relevant to the question |
| `examples/` | Working code the agent can point to or adapt |
| `commands/*.md` | Slash command definitions — predefined prompt templates for repeatable workflows |

### When a Skill Activates

Skills activate in two ways:

1. **Automatic** — Claude recognises platform engineering patterns in your question (Kubernetes manifest, Terraform code, Flux error, Helm chart, GitHub Actions workflow, etc.) and routes to the relevant section of the skill
2. **Explicit** — you use a slash command like `/platform-skills:review` to directly invoke a workflow

### What the Agent Actually Does

When you ask a platform question with `platform-skills` installed:

```
You: My Flux Kustomization is stuck in a NotReady state after a merge.

Claude:
  1. Reads SKILL.md → identifies this as a Flux reconciliation problem
  2. Reads references/flux.md → loads reconciliation troubleshooting section
  3. Asks for or reads your Kustomization manifest and Flux events
  4. Classifies the failure type (source | artifact | reconciliation | runtime)
  5. Produces: symptom → evidence to collect → hypothesis → fix → validation → rollback
```

The agent is not retrieving a pre-written answer. It is reasoning from your actual files against the platform knowledge in the skill.

---

## How to Use the Skills Effectively

### Be Concrete

The skill works best when you give it real artifacts. Vague questions get vague answers.

| Weak | Strong |
|------|--------|
| "How do I set up Flux?" | "I'm bootstrapping Flux on EKS with a monorepo. Here's my cluster/ directory. Is the structure correct and what am I missing?" |
| "Is this Terraform good?" | "Review this Terraform module for an EKS cluster. Flag IAM risks, replacement risk, and anything that would fail tflint." |
| "My Helm chart is broken" | "Here's my Helm chart. `helm lint --strict` throws two warnings. Help me fix them and check if my securityContext is correct." |

### Include What Matters

Good context to include:

- The file or manifest (paste it directly or reference the path)
- The exact error message or command output
- Which cloud provider, cluster type, or tool version
- What you are trying to achieve
- What you have already tried

### Use Slash Commands for Repeatable Work

Slash commands are predefined workflows. Use them instead of writing a long prompt from scratch.

| Command | When to use |
|---------|------------|
| `/platform-skills:review` | You have a manifest, Terraform file, or workflow and want a production-readiness check |
| `/platform-skills:terraform` | You want the full fmt/validate/tflint/security pipeline run against your Terraform |
| `/platform-skills:debug` | You have a platform symptom and want structured diagnosis |
| `/platform-skills:gitops` | Flux or Argo CD is not reconciling as expected |
| `/platform-skills:helmcheck` | You want to create, review, or security-audit a Helm chart |
| `/platform-skills:linkerd` | mTLS, proxy injection, or traffic policy issues |
| `/platform-skills:linux` | DNS, load balancer, VPC connectivity, or kernel issue |
| `/platform-skills:compliance` | SOC 2 gap analysis or Checkov remediation for Terraform |
| `/platform-skills:product` | RFC/ADR drafting, DevEx audit, incident communication, post-mortem |
| `/platform-skills:mcp` | Scaffold, review, or debug an MCP server or client |
| `/platform-skills:observability` | Instrument services, build dashboards, write alerts, run load tests, plan capacity |
| `/platform-skills:document` | Generate docstrings, OpenAPI specs, documentation sites, or getting started guides |
| `/platform-skills:datadog` | Datadog Agent setup, APM instrumentation, monitors, dashboards, SLOs, and debugging |
| `/platform-skills:dynatrace` | OneAgent deployment, instrumentation, anomaly detection, SLOs, and debugging |
| `/platform-skills:commit` | Write a commit message, generate a commit, describe staged changes, or validate a message |
| `/platform-skills:opa` | Generate Rego policies, write unit tests, run fmt/regal/verify pipeline, explain or debug |
| `/platform-skills:kyverno` | Generate, test, audit, debug, or migrate Kyverno admission policies |
| `/platform-skills:pr-review` | Comprehensive PR review: cost, drift, ownership, compliance, upgrade, rollback |
| `/platform-skills:triage` | Triage a PR comment, fix valid findings, reply, and resolve the thread |
| `/platform-skills:keda` | KEDA ScaledObject/ScaledJob — generate, debug, review, or design a scaling strategy |

Invoke a command by typing it at the start of your message:

```text
/platform-skills:helmcheck review

apiVersion: v2
name: payments-api
...
```

---

## How the Review Workflow Works

`/platform-skills:review` is the general-purpose production-readiness command. It accepts any platform artifact: Kubernetes manifest, Terraform file, GitHub Actions workflow, Helm values, or Helm chart.

### What It Checks

The review runs in this priority order — the same order an experienced platform engineer applies:

1. **Correctness** — API versions current, required fields present, references consistent, will it do what the author intends?
2. **Security** — least privilege, secrets handled safely, containers non-root, actions SHA-pinned, IAM scoped
3. **Operational safety** — rollback path, blast radius, resource limits, health checks, prune behaviour
4. **Deprecations** — deprecated APIs, outdated action versions, fields removed in the next minor
5. **Summary** — findings separated into Critical (must fix), Improvement (should fix), Note (informational)

### How to Invoke It

Paste the content directly:

```text
/platform-skills:review

apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments-api
...
```

Or describe what to review:

```text
/platform-skills:review

Review my GitHub Actions workflow at .github/workflows/deploy.yml — it uses OIDC to deploy to EKS after PR merge. Check for unsafe trigger usage, least-privilege permissions, and whether the steps can be pinned more safely.
```

### What You Get Back

```
REVIEW — payments-api Deployment

CRITICAL
- No resource requests or limits. Pods can starve the node.
  Fix: add resources.requests and resources.limits to every container.

IMPROVEMENT
- readOnlyRootFilesystem not set. Container has a writable root.
  Fix: set securityContext.readOnlyRootFilesystem: true; mount emptyDir at /tmp.
- No PodDisruptionBudget. Node drain will terminate all replicas simultaneously.
  Fix: add a PDB with minAvailable: 1.

NOTE
- imagePullPolicy defaults to Always when tag is latest. Use a pinned tag and IfNotPresent.
```

---

## How the Skill Fits Into Your Workflow

A practical loop for any platform task:

```
1. Identify the problem
   → Is this a Terraform change? A GitOps issue? A Helm chart? A runtime failure?

2. Choose the right layer
   → Terraform owns cloud primitives and cluster bootstrap
   → Kubernetes/OpenShift owns runtime workload model
   → Flux or Argo CD reconciles in-cluster state
   → GitHub Actions validates, packages, and promotes

3. Run the matching command or ask directly
   → /platform-skills:terraform for IaC review
   → /platform-skills:debug for a running system problem
   → /platform-skills:review for any config file

4. Apply the smallest safe change first
   → Review the blast radius before applying
   → Keep rollback steps ready

5. Validate before expanding
   → Run the validation commands from the response
   → Confirm the fix before moving to the next issue
```

---

## How the PR Review Workflow Works

`/platform-skills:pr-review` is the structured pre-merge risk review command. It accepts a PR number or a pasted diff and reviews it across six independent dimensions. Each mode produces severity-rated findings with concrete recommendations and, where relevant, exact remediation code.

### Getting the diff

```bash
# Pipe the diff into your clipboard
gh pr diff 42 | pbcopy   # macOS

# Or write it to a file
gh pr diff 42 > pr-42.diff
```

Then paste it after the command:

```text
/platform-skills:pr-review full

[paste diff here]
```

### The six modes

#### cost — spend delta

Inspects compute, storage, and network changes for their cost impact. Compares instance types, replica counts, PVC sizes, NAT Gateways, and load balancers against AWS pricing benchmarks.

```text
/platform-skills:pr-review cost

[diff showing replicas: 2 → 8 on a Deployment using m5.xlarge nodes]
```

Output:
```
[COST] payments-api Deployment — replicas increased from 2 to 8
  Estimated delta: +$840/month (8× m5.xlarge On-Demand)
  Severity: HIGH
  Recommendation: Use HPA with minReplicas: 2 so floor cost stays low outside peak.
```

See: [examples/pr-review/cost/](examples/pr-review/cost/)

#### drift — environment alignment

Checks whether a change applied to one environment's config (Helm values, Kustomize overlay, Terraform workspace) was intentionally omitted from sibling environments or silently missed. Flags any security controls that differ across environments as HIGH.

```text
/platform-skills:pr-review drift

values-dev.yaml: [paste]
values-prod.yaml: [paste]
```

Output:
```
[DRIFT] values-dev.yaml vs values-prod.yaml
  Field: ingress.annotations."nginx.ingress.kubernetes.io/ssl-redirect"
  Dev: "true"   Prod: MISSING (chart default: "false")
  Severity: HIGH — prod ingress does not force HTTPS; dev does
  Recommendation: Add ssl-redirect: "true" to values-prod.yaml
```

See: [examples/pr-review/drift/](examples/pr-review/drift/)

#### ownership — governance gaps

Reviews whether new directories, namespaces, Terraform modules, and PRs have the ownership signals that make a platform operable at scale: CODEOWNERS entries, team labels, module READMEs, and variable descriptions.

```text
/platform-skills:pr-review ownership

[diff adding a new platform/ directory and a Kubernetes Namespace]
```

Output:
```
[OWNERSHIP] platform/ — new top-level directory
  Gap: No CODEOWNERS entry. Any engineer can self-merge PRs to this path.
  Severity: HIGH
  Recommendation: Add to .github/CODEOWNERS:
    platform/   @platform-team @platform-leads
```

See: [examples/pr-review/ownership/](examples/pr-review/ownership/)

#### compliance — SOC 2 control impact

Maps every relevant change in the diff to a SOC 2 Trust Services Criteria control area (CC6.1–CC8.1, A1.2). Flags critical findings that would block an audit, provides exact Terraform remediations, and outputs the `aws` CLI commands auditors need to verify the control.

```text
/platform-skills:pr-review compliance

[diff with wildcard IAM policy and unencrypted RDS]
```

Output:
```
[COMPLIANCE] CC6.1 — Logical access
  Finding: aws_iam_role_policy.app uses Action: "*" Resource: "*"
  Severity: CRITICAL
  Remediation: Replace with explicit actions scoped to required services.
  Auditor evidence: aws iam simulate-principal-policy ...
```

See: [examples/pr-review/compliance/](examples/pr-review/compliance/)

#### upgrade — deprecated API and version hygiene

Checks every `apiVersion` in the diff against the Kubernetes deprecation timeline, flags Terraform provider constraints that allow major version jumps, identifies GitHub Actions pinned to branches instead of SHAs, and finds `:latest` container image tags.

```text
/platform-skills:pr-review upgrade

[diff with networking.k8s.io/v1beta1 Ingress and >= 3.0 provider constraint]
```

Output:
```
[UPGRADE] ingress.yaml:1 — networking.k8s.io/v1beta1 Ingress
  Removed in: Kubernetes 1.22 — BREAKING
  Replacement: apiVersion: networking.k8s.io/v1
  Migration effort: LOW
```

See: [examples/pr-review/upgrade/](examples/pr-review/upgrade/)

#### rollback — feasibility score

Scores each change on two axes: **Reversibility** (FULL / PARTIAL / MANUAL / NONE) and **Blast radius** (LOCAL / CLUSTER / PLATFORM / DATA). Produces a traffic-light Rollback Risk Score and lists the exact pre-merge requirements for anything that is not fully reversible.

```text
/platform-skills:pr-review rollback

[diff with RDS allocated_storage increase and Deployment rename]
```

Output:
```
[ROLLBACK] aws_db_instance.payments — allocated_storage 100 → 500 GB
  Reversibility: NONE — AWS does not support storage decrease
  Blast radius: DATA
  Pre-merge requirement: Take manual RDS snapshot and record ARN in PR description

Rollback Risk Score: 🔴 HIGH
```

See: [examples/pr-review/rollback/](examples/pr-review/rollback/)

### full mode — Merge Readiness Summary

Run all six modes in sequence and get a single consolidated summary:

```text
/platform-skills:pr-review full 42
```

```
Cost delta:      +$840/month (2 findings)
Drift:           3 environment mismatches
Ownership gaps:  2 findings
Compliance:      2 control areas affected (2 critical)
Upgrade risk:    2 deprecated items (2 breaking)
Rollback score:  🔴 HIGH

Blockers (must fix before merge):
  - Wildcard IAM action and resource (CC6.1)
  - RDS storage_encrypted = false (CC6.7)
  - networking.k8s.io/v1beta1 Ingress (removed in K8s 1.22)
  - RDS storage increase — take snapshot first (Reversibility: NONE)

Recommended:
  - Add ssl-redirect annotation to values-prod.yaml
  - Add CODEOWNERS entry for platform/

Informational:
  - replica increase adds $840/month; confirm with team before merge
```

### What the agent does under the hood

```
You: /platform-skills:pr-review compliance [paste diff]

Claude:
  1. Reads commands/pr-review.md → loads compliance mode definition
  2. Reads references/pr-review.md → loads SOC 2 control mapping table
  3. Reads references/compliance.md → loads Terraform patterns and evidence commands
  4. Parses the diff — identifies IAM, RDS, S3, and network resource changes
  5. Maps each change to a TSC control code
  6. For each finding: produces severity, exact remediation, and auditor evidence command
```

---

## What the Agent Cannot Do

Be clear about the limits:

- **It cannot read live cluster state** unless you give it `kubectl` output. Paste the output of `kubectl describe`, `kubectl get events`, or `flux get` into the conversation.
- **It cannot guarantee its knowledge is current.** Tool APIs change. Always cross-check against the official documentation for the exact version you are running.
- **It will not invent Terraform provider arguments** that do not exist. If it is unsure whether an attribute exists, it will say so.
- **It does not push or apply changes** unless you explicitly run the suggested commands yourself.

---

## Further Reading

- [GETTING_STARTED.md](GETTING_STARTED.md) — context on the platform operating model and how to frame questions
- [QUICKSTART.md](QUICKSTART.md) — install and first prompt in under 5 minutes
- [SKILL.md](SKILL.md) — the core routing rules the agent follows
- [references/](references/) — deep-dive guides for each domain
- [examples/](examples/) — working code to copy and adapt
