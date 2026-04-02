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

- **FluxCD troubleshooting patterns** for common reconciliation failures
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
- [Related patterns](../references/platform-operating-model.md)
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
See [FluxCD patterns](references/flux.md) for details.
```

Use absolute links for external resources:
```markdown
See [AWS IAM docs](https://docs.aws.amazon.com/iam/) for reference.
```

## Development Setup

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
# Install skill locally
claude-code skill install .

# Test skill activation
# (Open Claude Code and try relevant prompts)

# Uninstall after testing
claude-code skill uninstall platform-skills
```

## Release Process

### For Maintainers

Platform Skills uses automated GitHub Actions workflows for releases.

#### Quick Release Steps

1. **Update version and changelog:**
   ```bash
   # Update marketplace.json
   vim .claude-plugin/marketplace.json  # Set "version": "1.0.0"
   
   # Update CHANGELOG.md
   vim CHANGELOG.md  # Add [1.0.0] section with changes
   
   # Commit
   git add .
   git commit -m "Prepare v1.0.0 release"
   git push origin main
   ```

2. **Create and push tag (triggers automated release):**
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```

3. **Automated workflow handles:**
   - ✅ Version validation
   - ✅ Quality checks (markdown, YAML, Terraform, security)
   - ✅ GitHub Release creation with changelog
   - ✅ Marketplace publication preparation

4. **Verify release:**
   - GitHub Release created automatically
   - Release notes extracted from CHANGELOG.md
   - Tag and version match

5. **Distribution:**
   
   This repository is distributed through multiple channels:
   - **Claude Marketplace**: Primary distribution for end users (currently requires manual publication)
   - **GitHub Repository**: Browse patterns on GitHub, clone for customization
   - **Local Installation**: Install from local clone for testing and organization-specific modifications
   
   **Current state:** Marketplace publication is manual (see Marketplace Publication section below).
   **Future state:** When Claude marketplace API is available, publication will be automated via GitHub Release workflow.

#### Versioning

Follow semantic versioning:

- **Major (X.0.0)**: Breaking changes to skill structure
- **Minor (1.X.0)**: New patterns, features, or significant enhancements
- **Patch (1.0.X)**: Bug fixes, documentation improvements

#### Pre-Release Checklist

Before creating a tag:

- [ ] All PRs merged to main
- [ ] Version updated in `.claude-plugin/marketplace.json`
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
   claude-code skill publish .
   ```
3. Or submit via Claude marketplace publisher portal

**Future (Automated):**
- When Claude marketplace API is available, publication will be fully automated
- The workflow has placeholder steps ready to uncomment

#### Post-Release

After marketplace publication:

- [ ] Verify marketplace installation: `claude-code skill install platform-skills`
- [ ] Verify local installation: `claude-code skill install ./platform-skills`
- [ ] Update README badges if needed
- [ ] Announce release (optional)
- [ ] Monitor issues for feedback

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
