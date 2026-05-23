# Changelog

All notable changes to the `configure-cloud` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release — AWS and Azure OIDC credential configuration in a single action
- AWS: `aws-actions/configure-aws-credentials` with OIDC role assumption and `role-session-name`
- Azure: `azure/login` with federated credentials (no client secret)
- Input validation: `cloud_provider` enum check; conditional required-field checks per provider
- `aws_account_id` output for downstream steps
- Verification step per provider with `::group::` log grouping
- Job summary with provider, region/subscription, and auth method
