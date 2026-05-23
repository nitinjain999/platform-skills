# Changelog

All notable changes to the `notify-slack` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release
- Webhook URL masked immediately with `::add-mask::` before any other step runs
- Payload built via `printf` (no heredoc quoting issues)
- Channel override support
- `@mention` support on failure via `mention_on_failure` input
- `status_emoji` and `http_status` outputs
- Input validation: webhook URL format check, status enum validation
- Job summary with status, HTTP code, and channel
