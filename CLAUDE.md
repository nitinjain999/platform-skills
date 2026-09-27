# Platform Skills - Skill Development Guide

This document explains the philosophy, structure, and development principles for the Platform Skills Claude Agent Skill.

## Philosophy

### Production-First Engineering

Platform Skills embodies a production-first mindset:

- **Root-cause analysis over symptoms** - Don't just fix the error; understand why it happened
- **Blast radius awareness** - Every change has consequences; document them
- **Rollback plans are mandatory** - If you can't undo it safely, don't do it
- **Security by default** - Least privilege, defense in depth, assume breach

### Progressive Disclosure

Information architecture follows progressive disclosure:

1. **SKILL.md** - Essential patterns and problem classification
2. **references/** - Deep dives into specific domains
3. **examples/** - Concrete, copy-paste-able implementations

Users get quick answers from SKILL.md, detailed guidance from references, and working code from examples.

### Multi-Domain Coherence

Platform engineering spans multiple tools. This skill maintains coherence by:

- **Defining ownership boundaries** - Which tool owns which concern
- **Establishing contracts** - How tools interact (Terraform → GitOps reconciler → Apps)
- **Preventing overlap** - Don't recreate in GitOps what Terraform manages
- **Standardizing patterns** - Same approach across AWS and Azure where applicable

## Writing Principles

### 1. Start with the Problem

Bad:
> Use `flux reconcile kustomization` to sync changes.

Good:
> **Problem:** Changes merged to Git but cluster not updating
> 
> **Diagnosis:** Check reconciliation status with `flux get kustomizations`
> 
> **Fix:** Force immediate sync with `flux reconcile kustomization <name>`
> 
> **Prevention:** Reduce `.spec.interval` for faster automatic syncs

### 2. Make Security Explicit

Bad:
```yaml
Action: "s3:*"
Resource: "*"
```

Good:
```yaml
# ❌ Overly permissive
Action: "s3:*"
Resource: "*"

# ✅ Least privilege
Action:
  - "s3:GetObject"
  - "s3:ListBucket"
Resource:
  - "arn:aws:s3:::my-bucket"
  - "arn:aws:s3:::my-bucket/*"
```

### 3. Document Blast Radius

Every risky operation needs:
- **What it affects** - Scope of changes
- **What can break** - Known failure modes
- **How to verify** - Post-change validation
- **How to rollback** - Safe undo path

Example:
> **Blast radius:** Deletes all Kustomizations in namespace, triggering removal of managed resources
> 
> **Verification:** `kubectl get all -n <namespace>` should show expected resources gone
> 
> **Rollback:** Flux will recreate from Git on next sync (default 10m) or force with `flux reconcile`

### 4. Use Concrete Examples

Avoid abstract placeholders:

Bad:
```yaml
name: foo
namespace: bar
value: baz
```

Good:
```yaml
name: nginx-ingress
namespace: ingress-system
value: production
```

### 5. Explain Non-Obvious Choices

When configuration isn't self-evident, add comments:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
spec:
  interval: 10m
  path: ./apps
  prune: true
  wait: true          # Block until resources are ready
  timeout: 5m         # Fail fast if stuck
  dependsOn:          # Requires infrastructure first
    - name: infrastructure
```

## Content Guidelines

### Problem Classification

Every troubleshooting section should classify issues by:

1. **Layer** - Source, Artifact, Reconciliation, Runtime
2. **Symptoms** - Observable errors or behaviors
3. **Evidence collection** - Commands to run
4. **Common causes** - Typical root causes
5. **Fix patterns** - Concrete solutions
6. **Prevention** - How to avoid in future

### Decision Frameworks

When presenting choices, use decision matrices:

| Scenario | Recommended | Reason |
|----------|------------|---------|
| Environment differences | Kustomize | Simple overlays |
| Third-party apps | Helm | Version controlled |
| Complex parameterization | Helm | Type checking |

### Code Examples

All code examples must:
- Be syntactically valid
- Use realistic names and values
- Include necessary context (API versions, required fields)
- Show validation commands
- Note prerequisites or dependencies

### Security Patterns

Security guidance must:
- Default to least privilege
- Explain why more access is needed (if applicable)
- Show before/after for hardening changes
- Note compliance implications (GDPR, PCI, SOC2)
- Document audit and monitoring approaches

## Development Workflow

### Adding New Patterns

1. **Validate in production** - Patterns must be battle-tested
2. **Create issue** describing the gap
3. **Draft in appropriate file**:
   - Quick reference → `SKILL.md`
   - Detailed guide → `references/*.md`
   - Working example → `examples/*/`
4. **Follow structure** - Problem, Evidence, Fix, Prevention, Rollback
5. **Test in real environment** - Verify commands work
6. **Submit pull request** with context

### Updating Existing Patterns

1. **Identify what's wrong** - Outdated tool version? Missing edge case?
2. **Gather evidence** - Test updated approach
3. **Update relevant files** - May span SKILL.md, references, examples
4. **Update CHANGELOG.md** - Note what changed and why
5. **Submit pull request** with before/after comparison

### Review Checklist

Before submitting:

- [ ] Technically accurate?
- [ ] Security conscious?
- [ ] Includes rollback plan?
- [ ] Uses concrete examples?
- [ ] Follows existing structure?
- [ ] Links to related patterns?
- [ ] Updated CHANGELOG?
- [ ] Tested in real environment?

## Skill Maintenance

### Deprecation Policy

When removing patterns:
1. Mark as deprecated in current version
2. Explain why and suggest alternative
3. Remove in next major version
4. Update CHANGELOG with migration path

### Testing Strategy

Skill changes are tested by:
1. **Manual validation** - Try examples in real clusters
2. **Peer review** - Platform engineers review for accuracy
3. **User feedback** - Issues and discussions inform improvements
4. **Tool version tracking** - Note when tool updates require changes

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- How to propose changes
- Code of conduct
- Review process
- Release workflow

## Questions?

- **Skill design questions**: Open a discussion on GitHub
- **Content issues**: Open an issue on GitHub
- **Security concerns**: Use GitHub Security Advisories

## Agent Rules

Rules promoted from `.learnings/` — apply to every session in this project.

- Log errors and learnings at the point of discovery — never defer to end of session.
- Dispatch all independent tool calls in a single message block — sequential calls only when output feeds the next.
- Run `bash tests/handbook-consistency.sh` locally before every push to catch version/status/path check failures.
- Use `repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies` for PR thread replies — omitting the PR number returns 404.
- Never create `.learnings/` or `memory/` inside this repo. At the end of every session, append notable exchanges, decisions, and outcomes to `~/.claude/projects/<slug>/memory/YYYY-MM-DD.md` (today's date, created if missing). One file per day, append-only.
- Before every release commit, verify: (1) `SKILL.md` matches `skills/platform-skills/SKILL.md`, (2) `INSTALLATION.md` version matches plugin version, (3) all example READMEs have `Status:` label, (4) `marketplace.json` `source.sha` is the current main HEAD SHA.
- Never write SDK method names, parameter names, or env vars for external tools (Datadog, LLMObs, etc.) without fetching actual SDK source or docs first.
- Lambda@Edge child module: declaring `configuration_aliases = [aws.us_east_1]` requires a matching `provider "aws" { alias = "us_east_1" }` block inside the module or `terraform validate` fails (ERR-20260522-003)
- In Lambda@Edge viewer-request, `request.headers['set-cookie']` targets the origin, not the browser — use a forwarded header (`x-ab-bucket`) and set `Set-Cookie` in a viewer-response function (ERR-20260522-004)
- In GHA `run:` scripts, never use `${{ expr || expr }}` to pick between two context SHA values — assign each to a named `env:` var and resolve in shell; add `fetch-depth: 2` so `HEAD~1` is available as fallback (ERR-20260621-002)
- In `commands/secrets.md` sealed mode, Q2 asks for the controller **Service** name (used by `kubeseal --controller-name`), not the Deployment name — the two may differ; always use `kubectl get svc` for discovery (ERR-20260621-001)
