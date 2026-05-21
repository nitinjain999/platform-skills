# Security Policy

## Supported Versions

Platform Skills is a Claude Code skill plugin — it ships documentation and example configurations, not executable production code. Security guidance within the skill is kept current for the latest release.

| Version | Supported |
|---------|-----------|
| Latest (v1.x) | ✅ |
| Older releases | ❌ |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report security issues privately via [GitHub Security Advisories](https://github.com/nitinjain999/platform-skills/security/advisories/new).

Include in your report:
- Description of the vulnerability
- File(s) and section(s) affected
- Potential impact (e.g. a code example that produces an insecure configuration)
- Suggested fix if you have one

You will receive a response within **7 days**. If the issue is confirmed, a fix will be released as a patch and credited to you in the changelog (unless you prefer to remain anonymous).

## Scope

Security reports are relevant for:
- Example configurations that produce insecure infrastructure (overly permissive IAM, exposed secrets, missing encryption)
- Shell script examples with command injection or unsafe variable expansion
- GitHub Actions workflow examples with missing permission scoping or unpinned actions
- Reference guides that give actively harmful security advice

Out of scope:
- Theoretical risks with no realistic exploit path
- Issues in third-party tools referenced by this skill (report those upstream)
- The Claude Code platform itself (report via [Anthropic's responsible disclosure](https://www.anthropic.com/security))

## Security Philosophy

Platform Skills defaults to the most secure posture:
- Least-privilege IAM by default
- Pinned action SHAs over floating tags
- No secrets in examples — environment variables or secret managers only
- Explicit over implicit permissions

If you spot a pattern that contradicts this, please report it.
