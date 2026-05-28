# Getting Started

## Who this is for

**Platform engineers and developers** who want to understand how to use the handbook effectively — which tool owns what, how to ask good questions, and where to look for patterns.

If you are still setting up, start with [QUICKSTART.md](QUICKSTART.md) or [INSTALLATION.md](INSTALLATION.md) first, then come back here.

---

## Part 1 — For platform engineers

### The ownership model

Do not ask about tools in isolation. Ask from the platform point of view. Every infrastructure decision belongs to exactly one layer:

| Layer | Owns |
|---|---|
| **Terraform** | Cloud resources, cluster bootstrap, IAM, networking, secrets backends |
| **Kubernetes / OpenShift** | Workload specs, RBAC, network policy, resource limits |
| **Flux / Argo CD** | In-cluster state, HelmReleases, workload promotion |
| **GitHub Actions** | CI validation, artifact publish, promotion triggers |

**Critical rules:**

- Choose **either** Flux **or** Argo CD for a given ownership boundary — never both against the same boundary without a migration plan
- Terraform bootstraps; Flux/Argo CD reconciles. Flux does not manage cloud resources
- GitHub Actions does not store long-lived environment truth in workflow YAML

### Where to look in this repo

Start here based on your task:

| Task | File |
|---|---|
| Ownership boundaries and repo topology | [references/platform-operating-model.md](references/platform-operating-model.md) |
| Kubernetes baseline patterns | [references/kubernetes.md](references/kubernetes.md) |
| Terraform module and state design | [references/terraform.md](references/terraform.md) |
| FluxCD GitOps patterns (overview) | [references/fluxcd.md](references/fluxcd.md) |
| FluxCD source CRDs | [references/fluxcd-sources.md](references/fluxcd-sources.md) |
| FluxCD ResourceSet and fleet templating | [references/fluxcd-resourcesets.md](references/fluxcd-resourcesets.md) |
| FluxCD notifications (Alert, Receiver) | [references/fluxcd-notifications.md](references/fluxcd-notifications.md) |
| FluxCD Operator (FluxInstance, FluxReport) | [references/fluxcd-operator.md](references/fluxcd-operator.md) |
| FluxCD Kustomization advanced | [references/fluxcd-kustomization.md](references/fluxcd-kustomization.md) |
| FluxCD HelmRelease advanced | [references/fluxcd-helmrelease.md](references/fluxcd-helmrelease.md) |
| FluxCD Terraform bootstrap | [references/fluxcd-terraform.md](references/fluxcd-terraform.md) |
| FluxCD MCP server (AI debugging) | [references/fluxcd-mcp.md](references/fluxcd-mcp.md) |
| FluxCD API migration (v2.7/v2.8) | [references/fluxcd-migration.md](references/fluxcd-migration.md) |
| FluxCD security audit checklist | [references/fluxcd-security.md](references/fluxcd-security.md) |
| Argo CD patterns | [references/argocd.md](references/argocd.md) |
| AWS platform guidance | [references/aws.md](references/aws.md) |
| Azure platform guidance | [references/azure.md](references/azure.md) |
| GitHub Actions security | [references/github-actions.md](references/github-actions.md) |
| Composite GitHub Actions | [references/composite-actions.md](references/composite-actions.md) |
| SOC 2 controls in Terraform | [references/compliance.md](references/compliance.md) |
| Helm chart patterns | [references/helm.md](references/helm.md) |
| Kyverno admission policies | [references/kyverno.md](references/kyverno.md) |
| OPA / Conftest Rego policies | [references/opa.md](references/opa.md) |
| PR review dimensions | [references/pr-review.md](references/pr-review.md) |

Examples under `examples/` are meant to be adapted, not copied blindly into production.

### Good prompts

Include: what you are trying to do, which platform, which tool owns the change, the actual file or error, and the desired end state.

```
Review this Terraform layout for a multi-environment EKS platform. I want clear separation between reusable modules and live environment state.
[paste layout]
```

```
My Argo CD application is out of sync after a merge. Here is the manifest and sync status. What is the most likely root cause and what evidence should I collect first?
```

```
I run OpenShift on AWS. Should ingress, cert-manager, and observability be managed by Terraform or GitOps?
```

```
Review this GitHub Actions workflow for OIDC, least privilege, and unsafe trigger choices.
[paste workflow]
```

### Common mistakes to avoid

- Mixing Terraform and GitOps ownership for the same resource
- Using both Flux and Argo CD against the same boundary without a migration plan
- Asking broad questions without sharing the actual file, YAML, or error
- Treating examples in this repo as complete production systems without adapting them
- Putting environment truth into GitHub Actions workflow YAML

### Simple workflow loop

1. Identify the platform problem
2. Identify the owning layer
3. Open the matching reference file
4. Ask for a concrete recommendation or review
5. Apply the smallest useful change first
6. Validate before expanding the pattern

---

## Part 2 — For new Claude users

### How Claude uses this skill

When you install platform-skills as a Claude plugin, Claude automatically loads the right reference guide based on what you are working on. You do not need to tell Claude which file to read — it activates from context (the file types you paste, the tools you mention, the error text).

You can also invoke any workflow explicitly:

```
Using the kyverno workflow, generate a ValidatingPolicy that requires team labels
```

```
Using the pr-review rollback workflow, score the feasibility of this change
```

### How to get concrete answers

Claude works best with concrete input. Always include:

- the actual file or manifest (not a description of it)
- the exact error message
- the cluster, environment, or cloud provider
- the desired end state

**Too vague:**
```
How do I fix my Flux reconciliation?
```

**Concrete — gets a useful answer:**
```
My Flux Kustomization `apps` is stuck in NotReady with: "context deadline exceeded". I merged 20 minutes ago. Here is the output of `flux get kustomizations -A`:
[paste output]
```

### What the skill cannot do

- It cannot run `kubectl`, `terraform`, or `git` commands on your behalf — it explains what to run
- It cannot see your cluster or cloud account — paste the relevant output
- It works best on one concrete problem at a time, not "review everything"

### All 31 command workflows

See [COMMANDS.md](COMMANDS.md) for every command with modes and example prompts:

| Command | Use it for |
|---|---|
| `review` | Production-readiness check on any manifest, Terraform, workflow |
| `debug` | Structured troubleshooting for any platform symptom |
| `terraform` | Blast radius, IAM least privilege, SOC 2, state impact |
| `gitops` | Flux / Argo CD — `debug` live issues or `audit` a GitOps repo |
| `helmcheck` | Scaffold, review, or security-audit a Helm chart |
| `kyverno` | Generate, test, audit, or migrate Kyverno policies |
| `opa` | Generate, test, or debug OPA/Conftest Rego policies |
| `compliance` | SOC 2 gap analysis, control implementation, audit evidence |
| `pr-review` | Cost, drift, ownership, compliance, upgrade, rollback |
| `observability` | Instrument, alert, dashboard, load test, capacity |
| `commit` | Conventional commit message generation and validation |
| `linkerd` | mTLS, proxy injection, policy, multi-cluster diagnostics |
| `linux` | DNS, load balancer, VPC, process, disk, networking |
| `datadog` | Agent setup, APM, monitors, SLOs, incident investigation |
| `dynatrace` | Operator, instrumentation, SLOs, Davis AI investigation |
| `document` | Docstrings, OpenAPI specs, docs sites, guides |
| `mcp` | Scaffold, review, or debug an MCP server |
| `aws-profile` | Discover, switch, and validate AWS profiles for MCP servers |
| `product` | DevEx audit, RFC/ADR, incident update, post-mortem |
| `triage` | Use `/platform-skills:triage` to classify, fix, reply to, and resolve PR comments |
| `keda` | Use `/platform-skills:keda` to generate, debug, review, or design a KEDA scaling strategy |
| `self-improve` | Bootstrap `.learnings/` workspace, log errors and learnings, resume after interruption, promote to project memory |
| `supply-chain` | Sign images, generate SBOMs, run CVE gates, enforce image signatures, generate SLSA provenance |
| `runtime-security` | Deploy Falco with eBPF, write custom rules, route alerts, debug rule firing, bridge to Kyverno |
| `chaos` | Install Litmus Chaos or Chaos Mesh, generate fault experiments, schedule chaos, run GameDay, debug, report |
| `dora` | Instrument DORA metrics, generate Grafana dashboards, benchmark against performance bands, debug metric gaps |
| `awesome-docs` | Generate any animated Markdown doc (README, architecture guide, runbook, tutorial, RFC, post-mortem, or custom), convert existing Markdown, update/diff/audit diagrams, export |
| `aws` | Generate or review CloudFront, WAF, Lambda@Edge, CloudFront Functions, and Firewall Manager patterns |
| `composite-actions` | Scaffold, review, secure, debug, publish, and improve composite GitHub Actions |
| `fluxcd` | FluxCD entry point — routes to `gitops debug`, `gitops audit`, `helmcheck`, or `review` based on input |
| `renovate` | Generate renovate.json covering all dep file types in the repo, or emit a GHA validation workflow |

### How the agent and skill system work

If you want to understand what is happening under the hood — how Claude loads skills, what activates them, and what the agent can and cannot do — read [HOW_IT_WORKS.md](HOW_IT_WORKS.md).

---

## Next step

1. [QUICKSTART.md](QUICKSTART.md) — if you have not installed yet
2. [README.md](README.md) — domain table and repo overview
3. The one reference file closest to your current task
4. [COMMANDS.md](COMMANDS.md) — when you want to explore specific workflows
