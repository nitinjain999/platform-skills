# Contributing to Platform Skills

Thank you for your interest in contributing to Platform Skills! This guide will help you propose improvements and add new patterns.

## How to Contribute

### Reporting Issues

If you encounter problems or have suggestions:

1. **Search existing issues** first to avoid duplicates
2. **Open a new issue** with:
   - Clear problem description or feature request
   - Relevant context (cloud provider, tool versions, error messages)
   - Expected vs actual behavior
   - Minimal reproduction steps if applicable

### Proposing New Patterns

Before submitting a pattern:

1. **Check if it's truly a pattern** - Is it reusable across multiple scenarios?
2. **Verify it's production-tested** - Patterns should be battle-tested, not theoretical
3. **Ensure it follows principles** - Root-cause focused, security-conscious, operationally safe

### Pull Request Process

1. **Fork the repository** and create a feature branch
   ```bash
   git checkout -b feature/flux-troubleshooting-pattern
   ```

2. **Make your changes** following the structure:
   - **Core guidance** goes in `SKILL.md`
   - **Detailed patterns** go in `references/*.md`
   - **Practical examples** go in `examples/*/`
   - Update `CHANGELOG.md` with your changes

3. **Follow the writing style**:
   - Production-first mindset
   - Root-cause analysis over symptoms
   - Explicit blast radius and rollback plans
   - Clear prerequisites and assumptions
   - Concrete examples over abstract descriptions

4. **Test your changes**:
   - Validate markdown formatting
   - Test code examples in real environments
   - Ensure links work
   - Run spellcheck

5. **Submit pull request** with:
   - Clear title describing the change
   - Problem statement (what gap does this fill?)
   - Solution approach (how does this help users?)
   - Testing notes (how was this validated?)

### Content Guidelines

#### Problem Classification

When documenting issues, use this structure:

**Template:**

```
### Problem: [Concise description]

**Symptoms:**
- Observable behavior
- Exact error messages
- Impact on services

**Evidence to collect:**
Commands to gather diagnostic information

**Root cause:**
Clear explanation of why this happens

**Fix:**
Specific configuration changes with code blocks

**Validation:**
How to verify the fix worked

**Prevention:**
How to avoid this in the future

**Rollback:**
How to safely undo if needed
```

**Example:**

```markdown
### Problem: HelmRelease stuck in reconciling state

**Symptoms:**
- HelmRelease shows "Reconciling" for >10 minutes
- Error: "chart pull failed: failed to get chart version"
- Application pods not created

**Evidence to collect:**
`flux logs --kind=HelmRelease --name=my-app`
`kubectl describe helmrelease my-app -n apps`

**Root cause:**
HelmRepository source is unreachable or chart version doesn't exist

**Fix:**
Verify HelmRepository is ready and chart version exists in repository

**Validation:**
`flux get helmreleases` shows "Ready" status

**Prevention:**
Add health checks for HelmRepository before creating HelmReleases

**Rollback:**
`flux suspend helmrelease my-app` to stop reconciliation
```

#### Code Examples

- **Always include context** - Don't show snippets in isolation
- **Use realistic names** - `myapp`, `production`, `team-a` not `foo`, `bar`, `test123`
- **Show before and after** for configuration changes
- **Include validation commands** - How to verify it works
- **Add comments** explaining non-obvious choices

#### Security Guidance

When documenting security patterns:

- **Assume breach mindset** - Defense in depth
- **Least privilege by default** - Explain if more access is truly needed
- **Explicit over implicit** - Make security choices visible
- **Compliance awareness** - Note regulatory implications where relevant

### Review Process

All contributions are reviewed for:

1. **Correctness** - Is the guidance technically accurate?
2. **Clarity** - Can a platform engineer follow this?
3. **Safety** - Are risks and rollbacks documented?
4. **Consistency** - Does it match existing patterns?
5. **Value** - Does it solve real problems?

Reviewers may:
- Request changes for clarity or safety
- Suggest alternative approaches
- Ask for additional examples or validation
- Request tests in specific environments

### Community Guidelines

- **Be respectful** - We're all learning
- **Be constructive** - Suggest improvements, don't just criticize
- **Be specific** - "This is unclear" vs "Step 3 assumes X but doesn't explain it"
- **Be patient** - Reviewers are volunteers
- **Be collaborative** - Multiple iterations are normal

## What We're Looking For

### High Priority

- **Flux CD troubleshooting patterns** for common reconciliation failures
- **IAM policy examples** showing least-privilege patterns
- **GitHub Actions security fixes** for common vulnerabilities
- **Multi-cloud networking patterns** for hybrid environments
- **Disaster recovery runbooks** for platform components

### Medium Priority

- **Cost optimization patterns** across AWS/Azure
- **Observability integration** examples
- **Testing strategies** for infrastructure changes
- **Migration guides** between tool versions
- **Performance tuning** guidelines

### Lower Priority (But Still Welcome)

- **Alternative approaches** to existing patterns
- **Edge case handling** for documented patterns
- **Tool comparisons** with decision frameworks
- **Historical context** for architectural choices

## Documentation Standards

### File Structure

```markdown
# Title

Brief overview paragraph.

## Contents

- Section 1
- Section 2
- Section 3

## Section 1

Content here...

### Subsection

More specific content...

## Further Reading

- [External docs](https://example.com)
- [Related patterns](references/platform-operating-model.md)
```

### Code Block Standards

Always specify language:

```yaml
# Good - language specified
apiVersion: v1
kind: ConfigMap
```

~~~
# Bad - no language
apiVersion: v1
kind: ConfigMap
~~~

### Link Standards

Use relative links for internal docs:
```markdown
See [Flux CD patterns](references/flux.md) for details.
```

Use absolute links for external resources:
```markdown
See [AWS IAM docs](https://docs.aws.amazon.com/iam/) for reference.
```

## Development Setup

Before contributing, read [CLAUDE.md](CLAUDE.md) for the design philosophy, content structure, and writing principles that all patterns in this repository follow.

### Prerequisites

- Git
- Text editor with markdown support
- (Optional) Markdown linter
- (Optional) Vale for prose linting

### Recommended Tools

```bash
# Markdown linting
npm install -g markdownlint-cli

# Check markdown files
markdownlint '**/*.md' --ignore node_modules

# Spellcheck (if vale is installed)
vale references/*.md
```

### Testing Changes Locally

If you have Claude Code installed:

```bash
# Install plugin locally
claude plugin install .

# Test plugin activation
# (Open Claude Code and try relevant prompts)

# Uninstall after testing
claude plugin uninstall platform-skills
```

## Release Process

### For Maintainers

Platform Skills uses automated GitHub Actions workflows for releases.

#### Quick Release Steps

1. **Update version and changelog:**
   ```bash
   # Update marketplace.json
   vim .claude-plugin/marketplace.json  # Set plugins[0].version to "X.Y.Z"
   
   # Update CHANGELOG.md
   vim CHANGELOG.md  # Add [X.Y.Z] section with changes
   
   # Commit
   git add .
   git commit -m "Prepare vX.Y.Z release"
   git push origin main
   ```

2. **Create and push tag (triggers automated release):**
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. **Automated workflow handles:**
   - ✅ Version validation (tag matches marketplace.json)
   - ✅ Quality checks (markdown presence, YAML/JSON syntax, internal links, Terraform validation)
   - ✅ GitHub Release creation with changelog extraction
   - ✅ Marketplace publication preparation
   
   **Note:** Release workflow validates syntax and structure. For comprehensive validation including Kubernetes manifests and GitHub Actions security checks, use the standard PR workflow before tagging.

4. **Verify release:**
   - GitHub Release created automatically
   - Release notes extracted from CHANGELOG.md
   - Tag and version match

5. **Distribution:**
   
   This repository is distributed through multiple channels:
   - **Claude Marketplace**: Default end-user distribution for one-command install
   - **GitHub Repository**: Source of truth for the handbook, examples, and release history
   - **Local Installation**: Clone and install as a Claude plugin for testing or customization

   **Current state:** Marketplace publication is manual (see Marketplace Publication section below).
   **Future state:** When the Claude marketplace API is available, publication will be automated via the GitHub Release workflow.

#### Versioning

Follow semantic versioning:

- **Major (X.0.0)**: Breaking changes to skill structure
- **Minor (1.X.0)**: New patterns, features, or significant enhancements
- **Patch (1.0.X)**: Bug fixes, documentation improvements

#### Pre-Release Checklist

Before creating a tag:

- [ ] All PRs merged to main
- [ ] Version updated in `.claude-plugin/marketplace.json` (`plugins[0].version`)
- [ ] SHA in `.claude-plugin/marketplace.json` (`plugins[0].source.sha`) updated to the current HEAD commit — this field is not managed by Renovate and must be set manually
- [ ] CHANGELOG.md updated with release notes
- [ ] All CI checks passing
- [ ] Examples tested locally
- [ ] Documentation reviewed

#### Marketplace Publication

The release workflow provides marketplace publication instructions in the GitHub Release notes.

**Current Process (Manual):**

1. After GitHub Release is created, follow the instructions in the release summary
2. Use Claude Code CLI to publish:
   ```bash
   claude plugin publish .
   ```
3. Or submit via Claude marketplace publisher portal

**Future (Automated):**
- When Claude marketplace API is available, publication will be fully automated
- The workflow has placeholder steps ready to uncomment

#### Post-Release

After marketplace publication:

- [ ] Verify marketplace installation: `claude plugin install platform-skills`
- [ ] Verify local installation: `claude plugin install .`
- [ ] Update README badges if needed
- [ ] Announce release (optional)
- [ ] Monitor issues for feedback

## Automated Dependency Management

This repository uses [Renovate](https://docs.renovatebot.com/) for automated dependency updates.

### What Renovate Does

Renovate automatically:
- **GitHub Actions**: Updates action versions and maintains SHA pinning for security
- **Terraform**: Updates provider versions and module references
- **Helm Charts**: Updates chart versions in examples
- **Container Images**: Updates image tags in Kubernetes manifests
- **Vulnerability alerts**: Raises separate security-labelled PRs for CVE-flagged dependencies (handled by the `vulnerabilityAlerts` config block, separate from normal update rules)

### Reviewing Renovate PRs

When Renovate creates a pull request:

1. **Check the CI status** - All validation workflows must pass
2. **Review the changes** - Verify version compatibility
3. **Test if needed** - For major updates, test examples locally
4. **Merge promptly** - Security updates should be merged quickly

### Renovate Configuration

See [renovate.json](renovate.json) for the complete configuration. Key policies:

- **Automerge**: Terraform provider minor/patch; Helm chart patch only; stable patch updates for Terraform, Helm, Kubernetes, and docker-compose managers (non-0.x versions)
- **Manual review**: Required for GitHub Actions (all versions), Terraform modules, container images, and all major version bumps
- **Schedule**: Runs weekly on Mondays before 6am Berlin time
- **Grouping**: Related updates are grouped into single PRs

### Pausing Renovate

If you need to pause Renovate temporarily:

```bash
# Add a renovate.json field
{
  "enabled": false
}
```

Or use the Renovate dashboard to pause updates for specific dependencies.

## Questions?

- **General questions**: [Discussions](https://github.com/nitinjain999/platform-skills/discussions)
- **Bug reports**: [Issues](https://github.com/nitinjain999/platform-skills/issues)
- **Security issues**: Report via [GitHub Security Advisories](https://github.com/nitinjain999/platform-skills/security/advisories) (do not open public issues)

## License

By contributing, you agree that your contributions will be licensed under the Apache-2.0 License.

## Acknowledgments

Contributors will be recognized in:
- Release notes
- Contributors section in README
- GitHub contributors graph

Thank you for helping make platform engineering better for everyone!
