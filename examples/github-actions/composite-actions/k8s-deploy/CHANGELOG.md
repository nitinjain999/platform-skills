# Changelog

All notable changes to the `k8s-deploy` composite action.

## [Unreleased]

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
