# Changelog

All notable changes to the `configure-cloud` composite action.

## [Unreleased]

## [1.1.0] - 2026-05-24

### Added
- GKE cloud_provider path via Workload Identity Federation: `google-github-actions/auth` + credential verification step
- Five new GCP inputs: `gcp_workload_identity_provider`, `gcp_service_account`, `gcp_project`, `gcp_cluster_name`, `gcp_cluster_location`
- Input validation for all five GCP inputs when `cloud_provider=gke`
- Job summary updated to show GCP project when `cloud_provider=gke`
- SHA-pinned action refs: `google-github-actions/auth@6fc4af4b145ae7821d527454aa9bd537d1f2dc5f` (v2.1.7)
- `id-token: write` permission documented as required for all three cloud providers

## [1.0.0] - 2026-05-23

### Added
- Initial release — AWS and Azure OIDC credential configuration in a single action
- AWS: `aws-actions/configure-aws-credentials` with OIDC role assumption and `role-session-name`
- Azure: `azure/login` with federated credentials (no client secret)
- Input validation: `cloud_provider` enum check; conditional required-field checks per provider
- `aws_account_id` output for downstream steps
- Verification step per provider with `::group::` log grouping
- Job summary with provider, region/subscription, and auth method
