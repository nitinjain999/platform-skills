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

## Architecture

### Skill Activation

The skill activates when users work with:
- Flux CD or Argo CD reconciliation or GitOps repository design
- Kubernetes or OpenShift platform patterns
- AWS/Azure infrastructure or IAM/RBAC configuration
- Terraform modules or state management
- GitHub Actions workflows or CI/CD security
- Multi-cloud platform architecture decisions

Activation is automatic based on context, and users can also ask for platform-skills guidance explicitly in conversation.

### Content Structure

```
SKILL.md                      # Core skill definition
├── Activation triggers       # When to use this skill
├── Problem classification    # How to categorize issues
├── Troubleshooting framework # Consistent diagnostic approach
└── Best practices summary    # Quick reference patterns

references/                   # Deep-dive guides
├── platform-operating-model.md  # Cross-cutting architecture
├── kubernetes.md                # Cluster baseline patterns
├── openshift.md                 # OpenShift-specific guidance
├── argocd.md                    # Argo CD patterns
├── flux.md                      # GitOps patterns
├── aws.md                       # AWS-specific guidance
├── azure.md                     # Azure-specific guidance
├── terraform.md                 # IaC patterns
└── github-actions.md            # CI/CD patterns

examples/                     # Working implementations
├── flux/                     # GitOps repo structures
├── kubernetes/               # Kubernetes platform patterns
├── openshift/                # OpenShift operating patterns
├── argocd/                   # Argo CD examples
├── aws/                      # AWS service patterns
├── azure/                    # Azure resource patterns
├── terraform/                # Module examples
└── github-actions/           # Workflow templates
```

### Writing Principles

#### 1. Start with the Problem

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

#### 2. Make Security Explicit

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

#### 3. Document Blast Radius

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

#### 4. Use Concrete Examples

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

#### 5. Explain Non-Obvious Choices

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

### Version Strategy

Follow semantic versioning:
- **Major (2.0.0)** - Breaking changes to skill interface
- **Minor (1.1.0)** - New patterns or significant enhancements
- **Patch (1.0.1)** - Bug fixes or clarifications

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

## Integration with Claude Code

### Skill Discovery

Claude Code discovers this skill via:
- **Marketplace registration** - `.claude-plugin/marketplace.json`
- **Keyword matching** - Activates on relevant terms
- **Context awareness** - File types, commands, error messages

### Skill Invocation

Users can invoke via:
- **Automatic activation** - Working with relevant files
- **Explicit request** - Ask for platform-skills guidance in context
- **Context menus** - Right-click on errors or files

### Response Format

Claude Code expects:
- **Structured guidance** - Clear steps, not walls of text
- **Actionable commands** - Copy-paste ready
- **File references** - Links to relevant docs
- **Follow-up prompts** - Suggest next steps

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- How to propose changes
- Code of conduct
- Review process
- Release workflow

## Skill Quality Principles

1. **Correctness** - Technical accuracy is non-negotiable
2. **Safety** - Never suggest risky operations without warnings
3. **Clarity** - Platform engineers should understand immediately
4. **Completeness** - Include validation and rollback
5. **Maintainability** - Keep patterns up to date with tool changes

## Questions?

- **Skill design questions**: Open a discussion on GitHub
- **Content issues**: Open an issue on GitHub
- **Security concerns**: Use GitHub Security Advisories

---

Built with ❤️ by platform engineers, for platform engineers.
