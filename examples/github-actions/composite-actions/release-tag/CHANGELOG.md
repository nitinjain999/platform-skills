# Changelog

All notable changes to the `release-tag` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release
- Conventional commit auto-detection: `feat!`/`BREAKING CHANGE` → major, `feat:` → minor, fix/perf/refactor/docs → patch
- `$GITHUB_OUTPUT` chaining across 4 steps: bump → git_tag → changelog → create_release
- `is_new_release=false` skip path when no releasable commits found
- Branch guard: skips release when not on `release_branch`
- Draft and pre-release support
- Configurable `tag_prefix` and `changelog_sections`
- Outputs: `version`, `tag`, `release_url`, `is_new_release`
