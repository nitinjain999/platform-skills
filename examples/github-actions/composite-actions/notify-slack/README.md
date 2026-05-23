# notify-slack

> Send a build status notification to a Slack channel via an incoming webhook. The webhook URL is masked immediately and never appears in logs.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow and input carousel diagram. -->

## Quick start

```yaml
- uses: your-org/actions/notify-slack@v1
  if: always()   # notify on success AND failure
  with:
    webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}
    status: ${{ job.status }}
```

---

## Architecture

```
Job completes (success / failure / cancelled)
        │
        ▼
┌─────────────────────────────────────────────────────┐
│  notify-slack composite action                       │
│                                                      │
│  1. Validate inputs (status, webhook URL format)     │
│  2. ::add-mask:: webhook URL — never logs again      │
│  3. Build Slack JSON payload                         │
│     ├── Status emoji + colour (good/danger/warning)  │
│     ├── @mention on failure (optional)               │
│     └── Repo · branch · actor · run link             │
│  4. POST to Slack webhook (timeout: 1 min)           │
│  5. Write job summary                                │
└─────────────────────────────────────────────────────┘
        │
        ▼
Slack channel message
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `webhook_url` | string | **Yes** | **Yes** | — | Slack incoming webhook URL |
| `status` | choice | No | No | `${{ job.status }}` | `success` / `failure` / `cancelled` |
| `message` | string | No | No | `''` | Custom text appended to the notification |
| `channel` | string | No | No | Webhook default | Override channel (e.g. `#deployments`) |
| `actor` | string | No | No | `${{ github.actor }}` | Name shown in the notification |
| `run_url` | string | No | No | Link to the run | Override the run link |
| `mention_on_failure` | string | No | No | `''` | Slack user ID or `!here` to @mention on failure |

---

## Outputs

| Output | Description |
|---|---|
| `status_emoji` | Emoji representing the status (`✅` / `❌` / `⚠️`) |
| `http_status` | HTTP status code returned by the Slack API |

---

## Variables and secrets

`webhook_url` is the only secret. It must come from the caller's secrets store:

```
Caller secrets store
    SLACK_WEBHOOK_URL = https://hooks.slack.com/services/T.../B.../...
        │
        │  with:
        │    webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}
        ▼
inputs.webhook_url
        │
        │  echo "::add-mask::$WEBHOOK_URL"   ← masked immediately
        │  env: WEBHOOK_URL: ${{ inputs.webhook_url }}
        ▼
curl POST "$WEBHOOK_URL"   ← value is data, not code — safe from injection
```

**What is logged vs what is masked:**

| Value | Logged? |
|---|---|
| `inputs.status` | ✅ Yes — `success`, `failure`, or `cancelled` |
| `inputs.channel` | ✅ Yes — channel name is not sensitive |
| `inputs.mention_on_failure` | ✅ Yes — Slack user ID |
| `inputs.webhook_url` | ❌ No — masked as `***` immediately |
| Slack response body | ✅ Yes (on failure, to aid debugging) |

---

## Permissions

```yaml
permissions:
  contents: none   # no repository access needed
```

---

## Idempotency

**Not idempotent by design** — each call posts a new message or triggers an API call. To avoid duplicate notifications, call this action exactly once per job using `if: always()`.

---

## Concurrency

No concurrency concerns — each notification is independent.

---

## Full example — notify on every job outcome

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - run: npm ci && npm test

      - name: Notify Slack
        if: always()
        uses: your-org/actions/notify-slack@v1
        with:
          webhook_url: ${{ secrets.SLACK_WEBHOOK_URL }}
          status: ${{ job.status }}
          mention_on_failure: U01234ABCDE   # Slack user ID of the on-call engineer
```

---

## Setting up the Slack webhook

1. Go to `https://api.slack.com/apps` → Create App → From scratch
2. Add **Incoming Webhooks** feature → Activate
3. Click **Add New Webhook to Workspace** → select channel
4. Copy the webhook URL
5. Add to GitHub: **Settings → Secrets and variables → Actions → New secret** → name `SLACK_WEBHOOK_URL`

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
