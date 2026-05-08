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
