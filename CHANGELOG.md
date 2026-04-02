# Changelog

All notable changes to Platform Skills will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Expanded Flux CD troubleshooting patterns with real-world scenarios
- AWS EKS node group troubleshooting guide
- Azure AKS networking deep dive
- GitHub Actions security scanning workflow examples
- Terraform testing strategy comparison matrix
- Cost optimization patterns across AWS/Azure
- Disaster recovery runbooks for platform components
- Expand GCP coverage
- Add observability patterns (Prometheus, Grafana, Loki)
- Include service mesh guidance (Istio, Linkerd)
- Add policy-as-code examples (OPA, Kyverno, Gatekeeper)
- Add OpenShift operator lifecycle examples
- Expand Argo CD ApplicationSet fleet patterns

## [1.0.0] - 2026-04-02

Initial release of Platform Skills - A comprehensive Claude Agent Skill for platform engineering across 8 domains: Kubernetes, OpenShift, Argo CD, Flux CD, AWS, Azure, Terraform, and GitHub Actions.

### Added

#### Automation & CI/CD
- GitHub Actions workflow for automated releases (`.github/workflows/release.yml`)
  - Version validation and consistency checks
  - Quality checks (markdown, YAML, Terraform, security)
  - Automatic GitHub Release creation
  - Marketplace publication preparation
- GitHub Actions workflow for continuous validation (`.github/workflows/validate.yml`)
  - Repository structure validation
  - Markdown linting and link checking
  - YAML and Kubernetes manifest validation
  - Terraform format and validation checks
  - Security scanning for secrets and action pinning
- Consolidated release process documentation in CONTRIBUTING.md
- Removed redundant internal documentation (QUALITY_ASSURANCE.md, WORKFLOWS_SUMMARY.md)
- Cleaned up experimental files for production release
- Clarified distribution model: GitHub repository as primary distribution
- Fixed README structure (removed duplicate Installation headers)
- Updated marketplace.json with accurate repository URL and description

#### Core Features
- Initial release of Platform Skills
- Core skill definition in SKILL.md with activation triggers and troubleshooting framework
- GETTING_STARTED.md for new user onboarding
- Reference guides for 8 domains:
  - Platform Operating Model - Cross-cutting architecture and ownership patterns
  - Kubernetes - Cluster baselines, workload patterns, and policy defaults
  - OpenShift - Routes, SCC-aware workload design, operators, and tenancy
  - Argo CD - Projects, app-of-apps, ApplicationSet patterns, and promotion flows
  - Flux CD - GitOps reconciliation and repository structure patterns
  - AWS - Account model, EKS, IAM, and cloud foundations
  - Azure - Subscription model, AKS, RBAC, and resource management
  - Terraform - Module architecture, state management, and validation
  - GitHub Actions - Workflow security, reusability, and promotion patterns
- Working examples for all 8 domains:
  - Kubernetes: Namespace baselines, deployment patterns, network policy, pod disruption budgets
  - OpenShift: Routes, quotas, and platform-specific security adaptation
  - Argo CD: App-of-apps root application manifest
  - Flux CD: Complete monorepo structure with production and staging environments
  - AWS: IAM, VPC, EKS patterns
  - Azure: AKS, workload identity
  - Terraform: Production EKS module, multi-environment structures
  - GitHub Actions: Complete CI/CD pipelines, Flux sync validation, container builds
- Comprehensive README with installation and usage instructions
- Contributing guidelines for community participation
- Skill development guide (CLAUDE.md) with philosophy and patterns
- Apache-2.0 license with NOTICE file
- Claude Code marketplace integration (dual distribution: marketplace + local install)

### Core Principles Established
- Production-first mindset with blast radius awareness
- Root-cause analysis over symptom treatment
- Explicit rollback plans for all risky operations
- Security by default with least-privilege patterns
- Progressive disclosure from quick answers to deep dives

### Problem Classification Framework
- Kubernetes: Baseline standards, workload patterns, security controls, operational consistency
- OpenShift: Platform-specific constraints, GitOps integration, security and tenancy, day-2 operations
- Argo CD: Repository patterns, reconciliation model, promotion model, safety rules
- Flux CD: Source, Artifact, Reconciliation, Chart Rendering, Runtime issues
- AWS: Access/Auth, Network, Service-Specific, Cost, Compliance
- Azure: Access/Auth, Network, Service-Specific, Cost, Compliance
- Terraform: State Conflicts, Plan Failures, Apply Failures, Drift, Module Design
- GitHub Actions: Workflow Syntax, Permissions, Performance, Security, Reliability

### Troubleshooting Structure
- Symptom identification
- Evidence collection commands
- Hypothesis formation
- Diagnostic validation
- Specific fix with justification
- Verification steps
- Prevention strategies
- Rollback procedures

### Best Practices Documented
- Kubernetes: Platform baselines, workload patterns, security policies, operational rules
- OpenShift: Route patterns, SCC compatibility, operator usage, tenant isolation
- Argo CD: App-of-apps design, ApplicationSet patterns, sync control, promotion flows
- Flux CD: Reconciliation patterns, repository structures, multi-tenancy, progressive delivery
- AWS: IAM least privilege, tagging standards, EKS patterns, OIDC federation
- Azure: Managed identities, policy enforcement, AKS configuration, workload identity
- Terraform: Module conventions, state isolation, validation pipelines, testing strategies
- GitHub Actions: Security controls, reusable workflows, OIDC authentication, SHA-pinned actions

### Quality & Security Improvements
- Fixed workflow validation subshell issues - error counts now properly propagate
- Made Terraform validation blocking in release workflow
- SHA-pinned all GitHub Actions in examples (no mutable @v3/@v4 tags)
- Fixed tflint_version from "latest" to specific version (v0.50.3)
- Fixed malformed nested Markdown in contribution guidelines
- Updated all reference files to be reconciler-agnostic (supports both Flux CD and Argo CD)
- Fixed Argo CD example paths to reference existing repository structure
- Clarified dual distribution model: Claude marketplace (primary) + local installation (customization)

### Roadmap Items Completed
- ✅ Added Argo CD patterns alongside Flux CD
- ✅ Added Kubernetes platform baseline patterns
- ✅ Added OpenShift operating patterns

---

## Release Process

### Version Numbering

- **Major (X.0.0)**: Breaking changes to skill interface or structure
- **Minor (1.X.0)**: New patterns, reference guides, or significant enhancements
- **Patch (1.0.X)**: Bug fixes, clarifications, or minor updates

### What Warrants a Release

**Major Release:**
- Restructuring of core SKILL.md that changes skill behavior
- Breaking changes to reference file structure
- Removal of deprecated patterns

**Minor Release:**
- New reference guides (e.g., adding GCP patterns)
- Significant new troubleshooting sections
- New best practice patterns
- Tool version updates requiring new approaches

**Patch Release:**
- Typo fixes and clarifications
- Broken link fixes
- Command syntax updates
- Minor example improvements

### Release Checklist

Before releasing:

- [ ] Update version in `.claude-plugin/marketplace.json`
- [ ] Update this CHANGELOG with release notes
- [ ] Verify all examples work with current tool versions
- [ ] Test skill activation in Claude Code
- [ ] Review all external links
- [ ] Tag release in git: `git tag -a v1.0.0 -m "Release v1.0.0"`
- [ ] Push tag: `git push origin v1.0.0`
- [ ] Create GitHub release with changelog excerpt
- [ ] Update marketplace if applicable

---

## Tool Version Compatibility

### Current Testing Matrix

| Tool | Version | Last Verified |
|------|---------|---------------|
| Flux CD | 2.2+ | 2026-04-02 |
| Terraform | 1.5+ | 2026-04-02 |
| AWS CLI | 2.x | 2026-04-02 |
| Azure CLI | 2.50+ | 2026-04-02 |
| kubectl | 1.28+ | 2026-04-02 |
| Helm | 3.12+ | 2026-04-02 |

### Deprecation Notices

None currently.

---

## Migration Guides

### Upgrading from Pre-1.0

N/A - Initial release

---

## Contributors

Thank you to all contributors who helped build Platform Skills:

- [@nitinjain999](https://github.com/nitinjain999) - Initial skill design and implementation

See [CONTRIBUTING.md](CONTRIBUTING.md) to join this list!

---

## Links

- [Repository](https://github.com/nitinjain999/platform-skills)
- [Issues](https://github.com/nitinjain999/platform-skills/issues)
- [Discussions](https://github.com/nitinjain999/platform-skills/discussions)
- [Claude Code Marketplace](https://claude.ai/marketplace/skills)
