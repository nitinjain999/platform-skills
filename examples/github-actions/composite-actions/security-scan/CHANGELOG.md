# Changelog

All notable changes to the `security-scan` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release
- Trivy image, fs, and repo scan modes
- Severity enum validation with `::error::` fail-fast
- `registry_password` masked immediately with `::add-mask::`
- `::error::` annotations for CRITICAL findings, `::warning::` for HIGH findings
- SARIF output mode (`output_format: sarif`) for GitHub Code Scanning upload
- `fail_on_findings` gate with separate `evaluate` step
- Full scan output in job summary collapsible block
- Outputs: `vulnerability_count`, `scan_result`, `sarif_path`
