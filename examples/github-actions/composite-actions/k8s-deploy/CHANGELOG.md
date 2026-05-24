# Changelog

All notable changes to the `k8s-deploy` composite action.

## [Unreleased]

## [2.0.0] - 2026-05-24

### Breaking Changes
- Removed `kubeconfig` input — static base64 kubeconfig is no longer accepted
- Authentication now requires OIDC via the new `cloud_provider` input (`aws` | `azure` | `gke`)

### Added
- `cloud_provider` input: `aws`, `azure`, or `gke`
- EKS auth: `configure-aws-credentials` (OIDC) → `aws eks update-kubeconfig`
- AKS auth: `azure/login` (OIDC) → `az aks install-cli` + `az aks get-credentials` → `kubelogin convert-kubeconfig -l workloadidentity`
- GKE auth: `google-github-actions/auth` (WIF) → `google-github-actions/get-gke-credentials`
- Five new GCP inputs: `gcp_workload_identity_provider`, `gcp_service_account`, `gcp_project`, `gcp_cluster_name`, `gcp_cluster_location`
- `id-token: write` permission required on the calling job (was already required for AKS, now required for all paths)

### Migration from v1

```yaml
# v1 — static kubeconfig secret
- uses: your-org/actions/k8s-deploy@v1
  with:
    kubeconfig: ${{ secrets.KUBECONFIG }}
    namespace: production
    manifest_path: deploy/app.yml

# v2 — OIDC, no static secrets (EKS example)
- uses: your-org/actions/k8s-deploy@v2
  with:
    cloud_provider: aws
    aws_role_arn: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
    aws_cluster_name: my-cluster
    aws_region: us-east-1
    namespace: production
    manifest_path: deploy/app.yml
```

## [1.0.0] - 2026-05-23

### Added
- Initial release
- Base64 kubeconfig decoded to chmod-600 temp file, deleted in `if: always()` cleanup step
- `::add-mask::` on decoded kubeconfig content immediately after decode
- `--dry-run=server` support via `dry_run` input for validation without applying
- `kubectl rollout status` with configurable timeout and failure diagnostics (`kubectl events`, `kubectl describe pods`)
- Input validation: base64 format check, timeout pattern check, required field check
- Job summary with applied resources list
- Outputs: `rollout_status`, `applied_resources`
