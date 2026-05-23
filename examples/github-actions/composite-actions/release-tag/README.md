# release-tag

> Compute the next semantic version from conventional commits, create a git tag, and open a GitHub release with a generated changelog. Demonstrates `$GITHUB_OUTPUT` chaining across steps.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated lifecycle loop diagram. -->

## Quick start

```yaml
- uses: your-org/actions/release-tag@v1
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
```

---

## How version auto-detection works

The action reads conventional commit messages since the last semver tag:

| Commit message prefix | Bump |
|---|---|
| `feat!:` or `BREAKING CHANGE` | major |
| `feat:` | minor |
| `fix:`, `perf:`, `refactor:`, `docs:` | patch |
| No matching commits | Skip release |

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `github_token` | string | **Yes** | **Yes** | — | Token with `contents:write` |
| `version_type` | choice | No | No | `auto` | `major` / `minor` / `patch` / `auto` |
| `release_branch` | string | No | No | `main` | Branch allowed to release |
| `draft` | boolean | No | No | `false` | Create as draft release |
| `prerelease` | boolean | No | No | `false` | Mark as pre-release |
| `tag_prefix` | string | No | No | `v` | Tag prefix (e.g. `v` → `v1.2.3`) |
| `changelog_sections` | string | No | No | `feat,fix,perf,refactor,docs` | Commit types in changelog |

---

## Outputs

| Output | Description |
|---|---|
| `version` | Computed version (e.g. `1.4.0`) |
| `tag` | Full tag string (e.g. `v1.4.0`) |
| `release_url` | URL of the GitHub release |
| `is_new_release` | `true` if a release was created |

---

## $GITHUB_OUTPUT chaining — how outputs flow between steps

```
steps.bump.outputs.version  ──► steps.git_tag  (creates the tag)
                            ──► steps.changelog (changelog since previous tag)
                            ──► steps.create_release (release name + notes)
                            ──► action output: version, tag, is_new_release

steps.changelog.outputs.notes ──► steps.create_release (release body)

steps.create_release.outputs.release_url ──► action output: release_url
                                          ──► job summary
```

---

## Variables and secrets

Only `github_token` is a secret:

```yaml
# github_token flows like this:
secrets.GITHUB_TOKEN
    │
    │  with:
    │    github_token: ${{ secrets.GITHUB_TOKEN }}
    ▼
inputs.github_token
    │
    │  echo "::add-mask::$TOKEN"   ← masked immediately
    │  env: GH_TOKEN: ${{ inputs.github_token }}
    ▼
git push origin "$NEXT_TAG"        ← authenticated push
github-script                      ← creates release via REST API
```

---

## Permissions

```yaml
permissions:
  contents: write   # create tags and releases
```

---

## Idempotency

**Idempotent for the same set of commits.** If `version_type: auto` and the commits have not changed since the last run, the action detects no releasable commits and sets `is_new_release=false` without creating a duplicate tag.

**Not idempotent** when `version_type` is set to `major`/`minor`/`patch` — running twice creates two tags.

---

## Concurrency (recommended)

```yaml
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false   # never cancel a release in flight
```

---

## Full example

```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest

    concurrency:
      group: release-main
      cancel-in-progress: false

    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
        with:
          fetch-depth: 0   # full history for changelog generation

      - name: Release
        id: release
        uses: your-org/actions/release-tag@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          version_type: auto

      - name: Notify Slack
        if: steps.release.outputs.is_new_release == 'true'
        uses: your-org/actions/notify-slack@v1
        with:
          webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}
          status: success
          message: "Released ${{ steps.release.outputs.tag }} — ${{ steps.release.outputs.release_url }}"
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
