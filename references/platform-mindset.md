# Platform Mindset Reference

Guidance for platform engineers on treating developers as customers, communicating across teams, and proactively solving systemic problems.

---

## Product Mindset: Developers as Customers

### The Core Shift

A platform team that does not think like a product team builds infrastructure nobody uses. The shift:

| Infrastructure Team Thinking | Platform Product Thinking |
|-------------------------------|---------------------------|
| "We provide the tooling" | "We solve developer problems" |
| Feature-driven roadmap | Problem-driven roadmap |
| Adoption assumed | Adoption measured |
| Documentation as afterthought | Documentation as product surface |
| Support as interruption | Support as signal |

### Golden Paths

A golden path is the opinionated, supported, low-friction route from idea to production. It does not prevent other paths — it makes the right path the easy path.

**What a golden path covers:**
- Repo template with CI already wired
- Service scaffold with observability, secrets, and RBAC pre-configured
- One-command local environment that mirrors production
- Documented promotion flow: dev → staging → production
- Runbook template embedded in the service repo

**Anti-patterns:**
- Golden paths that require a ticket to the platform team to use
- Golden paths that only work for one language or framework
- Undocumented golden paths where knowledge lives in Slack

### Developer Portal (Backstage)

Backstage is the catalog and golden-path delivery surface. Use it to:
- Register every service with owner, runbook, on-call, and SLO metadata
- Surface software templates (scaffolding) for new services
- Display TechDocs alongside the service it documents
- Expose CI status, deploy history, and alert state in one place

**Catalog `catalog-info.yaml` minimum viable:**
```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: payments-api
  description: Handles payment processing
  annotations:
    github.com/project-slug: org/payments-api
    backstage.io/techdocs-ref: dir:.
spec:
  type: service
  lifecycle: production
  owner: group:payments-team
  system: checkout
```

### Measuring Developer Experience (DevEx)

Use the SPACE framework to avoid measuring only velocity:

| Dimension | Example Metrics |
|-----------|----------------|
| **S**atisfaction | Developer NPS, quarterly survey scores |
| **P**erformance | Deployment frequency, lead time, change failure rate |
| **A**ctivity | PR merge rate, pipeline success rate |
| **C**ommunication | PR review turnaround, incident MTTR |
| **E**fficiency | Time from commit to production, CI duration |

DORA four key metrics as a baseline:
- **Deployment frequency** — how often you deploy to production
- **Lead time for changes** — commit to production in minutes/hours
- **Change failure rate** — percentage of deployments causing incidents
- **MTTR** — time to restore after a failure

**Where to collect signals:**
- CI system (pipeline duration, failure rate)
- Git platform (PR age, review latency)
- Developer surveys (2x/year minimum)
- Support ticket volume and categories (most actionable signal for friction)

### Reducing Friction: The Audit Approach

Run a friction audit before starting roadmap planning:

1. **Shadow a developer** — watch them onboard a new service end-to-end
2. **Collect ticket categories** — group support requests by root cause
3. **Measure wait times** — how long does each handoff take?
4. **Ask "why five times"** — each manual step has a root cause removable by automation or documentation

Common friction sources and platform responses:

| Friction | Platform Response |
|----------|-------------------|
| "I don't know what secrets to set" | Self-service secret template in Backstage |
| "CI keeps failing on flaky tests" | Quarantine lane + test reliability SLO |
| "I have to wait for infra ticket" | Self-service Terraform module via Atlantis PR |
| "Staging is always broken" | Environment health dashboard, owner alerts |
| "I don't know who owns this" | Backstage catalog with on-call surfaced |

---

## Collaboration and Communication

### Working with Cross-Functional Teams

Platform engineers work across engineering, security, finance, and product. Each audience needs a different frame:

| Audience | What They Care About | How to Frame Platform Work |
|----------|---------------------|---------------------------|
| Engineering teams | Speed, reliability, not blocked | Reduce toil, faster deploys, self-service |
| Security | Risk, compliance, audit | Controls enforced by default, audit trail |
| Finance/FinOps | Cost, waste, forecast | Resource tagging, rightsizing, showback |
| Product/Leadership | Outcomes, not infrastructure | DORA metrics, incident reduction, time to market |

### Explaining Complex Technical Concepts

Follow the **Context → Problem → Solution → Trade-offs** structure:

**Context:** What is the system and who uses it?
**Problem:** What specific failure mode or gap exists?
**Solution:** What change addresses the root cause?
**Trade-offs:** What does the solution cost or constrain?

Avoid leading with the technology. Lead with the outcome.

Bad:
> "We need to implement a service mesh with mTLS and SPIFFE-based identity."

Good:
> "Services can currently make arbitrary calls to each other with no authentication. If one service is compromised, it can reach any other. We want to enforce that only the payments service can call the billing service — that requires identity at the network layer, which a service mesh provides."

### RFC and ADR Process

Use Request for Comments (RFC) for decisions that affect more than one team, and Architecture Decision Records (ADR) to capture what was decided and why.

**RFC template minimum:**
```markdown
# RFC: [title]

## Status: Draft | In Review | Accepted | Rejected

## Problem
What is broken or missing? Why does this matter now?

## Proposal
What change are you proposing? Be concrete.

## Alternatives considered
What else did you evaluate and why did you reject it?

## Impact
Which teams are affected? What migration is required?

## Open questions
What is not yet decided?
```

**ADR template minimum:**
```markdown
# ADR-0042: [title]

## Status: Accepted

## Context
What situation forced this decision?

## Decision
What did we decide?

## Consequences
What becomes easier? What becomes harder? What must we monitor?
```

Store ADRs in `docs/decisions/` in the relevant repo.

### Incident Communication

Structure incident updates for the broadest useful audience:

```
[STATUS] [SEVERITY] [COMPONENT] - [IMPACT STATEMENT]

Time: 14:32 UTC
Severity: SEV-2
Affected: Payment checkout — ~15% of transactions failing
Status: Investigating

What we know: Elevated error rate started at 14:28 after deploy of payments-api v2.3.1
What we are doing: Rollback in progress, ETA 10 minutes
Next update: 14:50 UTC or sooner if status changes
```

Avoid:
- Technical jargon in customer-facing updates
- Uncertainty about timelines without a next-update time
- Silence longer than 30 minutes during an active incident

### Post-Mortem / Blameless Retrospective

Structure:
1. **Timeline** — what happened, in order, with timestamps
2. **Impact** — duration, affected users, business impact
3. **Root cause** — the systemic cause, not the human who made a change
4. **Contributing factors** — what made the root cause possible
5. **Action items** — with owner and due date, not vague "improve X"

Blameless means: the system made it possible for a human to make that mistake. Fix the system.

---

## Problem-Solving at Scale

### Proactive Problem Identification

Do not wait for incidents. Use these signals to find problems before they surface:

| Signal | Where to Look | What to Ask |
|--------|---------------|-------------|
| Error budget burn rate | SLO dashboard | Which service is burning fastest? |
| P99 latency trends | APM (Datadog, Grafana) | What is climbing week-over-week? |
| CI failure rate | GitHub Actions / pipeline metrics | Which test is flaky? Which step adds 5 min? |
| Support ticket volume | Slack/Jira categories | What is the top category this sprint? |
| Cost anomalies | AWS Cost Explorer / Azure Cost Mgmt | What resource class is growing unexpectedly? |

### Systemic Fix vs. Local Fix

When a problem recurs, ask: is this a systemic issue or a local one?

**Local fix:** correct the specific instance.
**Systemic fix:** remove the class of problem.

| Problem | Local Fix | Systemic Fix |
|---------|-----------|--------------|
| Secret rotated manually | Rotate the secret | Automate rotation with ESO + Vault TTL |
| Developer opened port 22 | Close the port | AWS Config rule + auto-remediation Lambda |
| Helm values had wrong image tag | Fix the tag | Pin tags in CI artifact promotion |
| Node OOMKilled | Increase memory limit | Add VPA + alerting on limit utilization |

Prefer systemic fixes. Local fixes accrue as operational debt.

### Capacity Planning Framework

1. **Baseline current usage:** CPU, memory, storage per service per environment
2. **Project growth:** tie to a business metric (users, transactions, events/sec)
3. **Model headroom:** target 40% spare at peak for burst safety
4. **Define trigger thresholds:** at what utilization do you act?
5. **Review quarterly:** plans decay — schedule the review

### Cost Optimisation Loop

Run monthly:

1. Identify top 5 cost drivers by service/team tag
2. Check rightsizing recommendations (Compute Optimiser, Azure Advisor)
3. Review unused resources: stopped VMs, unattached volumes, idle NAT gateways
4. Surface to team with data, not blame
5. Set a target reduction with a deadline, track in the next cycle

---

## Reference Checklist: Platform Health Review

Run this quarterly with the team:

**Developer Experience**
- [ ] Onboarding a new service takes less than 1 day end-to-end
- [ ] CI pipeline p95 duration is under 10 minutes
- [ ] Developer NPS is above +30 (or improving)
- [ ] Support ticket volume is flat or declining

**Operations**
- [ ] All production services have SLOs with burn-rate alerts
- [ ] MTTR for SEV-2 incidents is under 30 minutes
- [ ] Post-mortems are completed within 5 business days
- [ ] Runbooks exist and were last tested within 90 days

**Security and Compliance**
- [ ] All cloud resources are tagged (tag policy enforced)
- [ ] No static credentials in CI; OIDC in use
- [ ] Secrets rotation is automated for all critical secrets
- [ ] IAM roles reviewed for wildcard actions in the last quarter

**Cost**
- [ ] Showback report shared with teams monthly
- [ ] Top 3 cost reduction actions have owners and due dates
- [ ] Rightsizing recommendations reviewed
