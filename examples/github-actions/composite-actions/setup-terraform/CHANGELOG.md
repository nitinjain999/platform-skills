# Changelog

All notable changes to the `setup-terraform` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release — Terraform install with provider plugin caching
- `hashicorp/setup-terraform` with configurable version and wrapper flag
- `actions/cache` keyed on `{os}-terraform-{version}-{lock-file-hash}` with version-scoped restore-keys
- `~/.terraformrc` plugin_cache_dir written automatically when `enable_cache=true`
- `working_directory` input for multi-module repos with different lock files
- Input validation: non-empty version check
- Outputs: `terraform_version`, `cache_hit`
- Job summary with version and cache status
- `::debug::` log entry when cache directory is created
