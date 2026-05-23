# pr-comment

> Post or update a structured comment on a pull request. Uses a hidden marker to upsert — running the same workflow twice updates the existing comment rather than creating a duplicate.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow diagram. -->

## Quick start

```yaml
- uses: your-org/actions/pr-comment@v1
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    title: Deployment Plan
    body: |
      | Environment | Status |
      |---|---|
      | staging | ✅ ready |
```

---

## Idempotent upsert pattern

Each comment is identified by a hidden HTML marker:

```html
<!-- pr-comment-action -->
## Deployment Plan
...
```

When the workflow runs again, the action finds the comment by its marker and updates it in place. This avoids comment spam on long-running PRs.

Set a unique `marker` per action instance when using multiple `pr-comment` steps in the same workflow:

```yaml
- uses: your-org/actions/pr-comment@v1
  with:
    marker: terraform-plan-staging
    title: Terraform Plan — staging
    ...

- uses: your-org/actions/pr-comment@v1
  with:
    marker: terraform-plan-production
    title: Terraform Plan — production
    ...
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `github_token` | string | **Yes** | **Yes** | — | Token with `pull-requests:write` |
| `title` | string | **Yes** | No | — | Comment heading |
| `body` | string | **Yes** | No | — | Comment body (Markdown) |
| `marker` | string | No | No | `pr-comment-action` | Unique marker for upsert |
| `update_existing` | boolean | No | No | `true` | Update existing comment |
| `delete_on_close` | boolean | No | No | `false` | Delete comment when PR closes |
| `icon` | string | No | No | `''` | Emoji prepended to title |
| `collapsible` | boolean | No | No | `false` | Wrap body in `<details>` |
| `collapsible_summary` | string | No | No | `Show details` | `<summary>` text |

---

## Outputs

| Output | Description |
|---|---|
| `comment_id` | ID of the created or updated comment |
| `comment_url` | URL of the comment |
| `action_taken` | `created` or `updated` |

---

## Variables and secrets

Only `github_token` is a secret:

```
secrets.GITHUB_TOKEN  (pull-requests: write)
    │
    │  with:
    │    github_token: ${{ secrets.GITHUB_TOKEN }}
    ▼
inputs.github_token
    │
    │  echo "::add-mask::$TOKEN"   ← masked immediately
    ▼
actions/github-script  ← authenticates REST API calls with the masked token
```

`body` and `title` are plain variables — they appear in the PR comment and job summary.

---

## Permissions

```yaml
permissions:
  pull-requests: write
```

No `contents` permission needed — this action only creates or updates PR comments.

---

## Idempotency

**Idempotent** — running twice updates the same comment. Change the `marker` if you need independent comments from the same workflow.

---

## Full example — collapsible plan comment with delete-on-close

```yaml
name: Terraform plan

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  plan:
    if: github.event.action != 'closed'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - id: plan
        uses: your-org/actions/terraform-plan@v1
        with:
          working_directory: terraform/
          github_token: ${{ secrets.GITHUB_TOKEN }}
          aws_role_arn: ${{ vars.AWS_PLAN_ROLE_ARN }}
          comment_on_pr: false   # use pr-comment action instead for full control

      - uses: your-org/actions/pr-comment@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          marker: terraform-plan-main
          icon: ${{ steps.plan.outputs.has_changes == 'true' && '⚠️' || '✅' }}
          title: Terraform Plan
          collapsible: true
          collapsible_summary: Show plan output
          delete_on_close: true
          body: |
            **Changes detected:** ${{ steps.plan.outputs.has_changes }}

            See the job summary for the full plan output.
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
