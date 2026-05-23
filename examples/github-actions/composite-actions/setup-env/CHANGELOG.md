# Changelog

All notable changes to the `setup-env` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release — based on the official GitHub Docs composite action tutorial
- Multi-runtime support: Node.js, Python, Go
- Per-runtime version defaults (node: 20.x, python: 3.12, go: 1.22.x)
- Dependency cache restore: npm (via `~/.npm`), pip (`~/.cache/pip`), Go modules (`~/go/pkg/mod` + `~/.cache/go-build`)
- Optional `install_dependencies` flag — runs `npm ci` / `pip install` / `go mod download`
- Input validation: runtime enum check with `::error::` fail-fast
- Outputs: `runtime_version`, `cache_hit`
- Job summary with runtime, version, cache status
