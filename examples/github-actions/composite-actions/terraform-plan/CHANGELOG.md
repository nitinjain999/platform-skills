# Changelog

All notable changes to the `terraform-plan` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release
- AWS and Azure OIDC dual-cloud support (no static credentials)
- Terraform provider cache with `actions/cache`
- fmt → validate → plan pipeline with `-detailed-exitcode`
- Idempotent PR comment upsert via hidden marker `<!-- terraform-plan:<dir> -->`
- Plan output truncated to 65,000 chars to stay within GitHub comment limits
- Outputs: `plan_exitcode`, `has_changes`
- Job summary with collapsible plan output
