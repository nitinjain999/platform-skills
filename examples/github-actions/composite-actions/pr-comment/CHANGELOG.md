# Changelog

All notable changes to the `pr-comment` composite action.

## [Unreleased]

## [1.0.0] - 2026-05-23

### Added
- Initial release
- Idempotent upsert via hidden HTML marker — running twice updates the same comment
- `listComments` with pagination to find existing comments
- Collapsible `<details>` wrapper via `collapsible` input
- `delete_on_close` support for PR closed event
- `update_existing` toggle to force always-create mode
- Icon/emoji prefix support
- Outputs: `comment_id`, `comment_url`, `action_taken`
