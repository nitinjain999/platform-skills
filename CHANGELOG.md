# Changelog

All notable changes to Platform Skills will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-04-02

### Added

#### Reference Guides
- Added RBAC troubleshooting to `references/kubernetes.md`: 401 vs 403 diagnosis, `kubectl auth can-i` evidence collection, binding scope matrix (Role/ClusterRole × RoleBinding/ClusterRoleBinding), `ClusterRoleBinding` audit query
- Added image automation section to `references/flux.md`: `ImageRepository`, `ImagePolicy`, `ImageUpdateAutomation` setup, registry auth table (GHCR/ECR/ACR/GAR/Docker Hub), troubleshooting table, safety rules for staging vs. production promotion
- Added `references/secrets.md`: decision matrix (ESO vs. Sealed Secrets), ESO setup for AWS/Azure/Vault/static credentials, Sealed Secrets seal/rotate/backup workflow, troubleshooting tables for both patterns, least-privilege IAM example, operational rules
- Added `references/secrets.md` to `REQUIRED_REFERENCES` in `tests/validate-skill.sh`

#### Plugin
- Bumped marketplace description and keywords to be developer-first (removed enterprise-only framing)
- Added keywords: `helm`, `docker`, `containers`, `deployment`, `rbac`, `secrets`, `security`, `gke`
- Updated SKILL.md activation description and body framing for discoverability by any developer
- Fixed `assignees` format in `renovate.json` (removed `@` prefix)
- Fixed `kubeconform` flag in `validate.yml`: `-skip-kinds` → `-skip` (correct flag name for v0.6.4)
- Fixed `LICENSE` copyright placeholder `[yyyy] [name of copyright owner]` → `2026 Nitin Jain`

## [1.1.0] - 2026-04-02

### Added

#### Reference Guides
- Expanded AWS reference with tagging guidance: `default_tags` provider block, ASG `propagate_at_launch`, EBS/Lambda propagation gaps, AWS Config `required-tags` rule, cost allocation tag activation steps, org-level tag policy enforcement
- Expanded Azure reference with tagging guidance: `merge(local.common_tags, {...})` pattern, tag inheritance gap explanation, Azure Policy `deny`/`modify` enforcement, remediation task for existing resources, AKS managed resource group tagging
- Added tagging rule to SKILL.md: enforce a baseline via provider-level mechanisms; specific keys are an organizational decision

#### Example Assets
- Added real example assets for previously stub domains: `examples/kubernetes/*.yaml` (4 files), `examples/openshift/*.yaml` (2 files), `examples/aws/iam/*.json` (2 files), `examples/azure/workload-identity/` (`main.tf` + `serviceaccount.yaml`)

#### Testing
- Added `tests/validate-skill.sh` — checks SKILL.md frontmatter, all reference files exist, each example domain has at least one asset beyond README.md, SKILL.md references every reference file; wired into `validate.yml` as a blocking CI job

#### Developer Experience
- Added `.github/copilot-instructions.md` — GitHub Copilot automatically applies Platform Skills patterns (no Claude Code required)
- Added `VSCODE_INTEGRATION.md` — comprehensive guide for VSCode with Claude Code extension, GitHub Copilot split-screen, and browser workflows
- Added `QUICKSTART.md` — 5-minute install and first-use guide
- Added `INSTALLATION.md` — full installation methods, team setup, troubleshooting

#### Dependency Management
- Scoped Renovate automerge catch-all rule to explicit managers (terraform, helmv3, kubernetes, docker-compose) to prevent accidental automerge of GitHub Actions

### Fixed

#### CI/CD Workflows
- Fixed `validate.yml` and `release.yml` marketplace.json validation — field paths now match marketplace format (`plugins[0].version`, `plugins[0].description`, etc.)
- Replaced deprecated `actions/create-release` (archived action) with `gh release create` CLI in `release.yml`
- SHA-pinned `hashicorp/setup-terraform` in `validate.yml` — floating `@v4.0.0` tag was causing the workflow's own security check to fail
- Removed unused `actions/setup-node` step from publish-marketplace job

#### Documentation
- Fixed dead Discord `#` placeholder link in README — replaced with real URL
- Added `QUICKSTART.md`, `INSTALLATION.md`, and `VSCODE_INTEGRATION.md` to README navigation and repository structure table
- Fixed hardcoded `v1.0.0` examples in CHANGELOG release checklist — replaced with `vX.Y.Z` placeholder
- Fixed Argo CD example Application `path:` fields — were pointing at Flux monorepo paths instead of Argo CD-appropriate paths
- Fixed Azure workload-identity `main.tf` — added `required_providers` block with minimum `azurerm >= 3.87.0`

### Changed

- README repositioned as handbook-first — skill layer described as optional, not the primary product
- Updated README repository structure tree to show real example files rather than `README.md`-only entries
- Trimmed VSCode install detail from README to a single pointer to VSCODE_INTEGRATION.md — install story now lives in one place
- Marketplace distribution: personal marketplace now named `platform-skills` (was `platform-skills-marketplace`)
- Owner contact updated to personal email
- All CLI command references updated: binary is `claude`, subcommand is `claude plugin` (not `claude-code skill`)

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
- Renovate configuration for automated dependency updates (`renovate.json`)
  - GitHub Actions SHA pinning with automatic updates
  - Terraform provider version management
  - Helm chart version tracking
  - Container image update monitoring
  - Security vulnerability alerts
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
- [ ] Tag release in git: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- [ ] Push tag: `git push origin vX.Y.Z`
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
