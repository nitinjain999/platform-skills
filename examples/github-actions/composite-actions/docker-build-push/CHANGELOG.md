# Changelog

All notable changes to the `docker-build-push` composite action.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This action adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release
- Multi-platform build via Docker Buildx (`linux/amd64`, `linux/arm64`)
- GHCR authentication via ephemeral `GITHUB_TOKEN` (no static credentials)
- GHA layer cache (`type=gha`) for faster repeated builds
- SLSA provenance and SBOM attestations on every push
- Input validation: `image_name` format check, fail-fast with `::error::` annotation
- Job summary with image URI, tag, digest, and platforms
- Outputs: `image_uri`, `image_digest`, `image_tag`
