# Changelog

All notable changes to the `db-migrate` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release — database migration with health check, verification, and job summary
- Multi-tool support: golang-migrate, Flyway, Liquibase — version-pinned installs
- `database_url` masked with `::add-mask::` before any tool output
- Database health check via `nc` with 10 retries before attempting migration
- `dry_run` mode — prints pending migrations without applying
- `verify_after` flag — post-migration schema version validation
- `lock_timeout_seconds` input — configurable wait for migration lock
- Outputs: `migrations_applied`, `current_version`, `dry_run_output`
- `if: always()` job summary with tool, directory, applied count, schema version
- `::group::` log grouping for health check, install, migrate, and verify phases
- `timeout-minutes` on health check (2m) and migration (15m) steps
- Rollback guidance in README (tool-specific commands, reversible migration advice)
