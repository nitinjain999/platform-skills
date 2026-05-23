# db-migrate

> Run database migrations safely with health check, advisory lock, verification, and automatic summary. Supports Flyway, Liquibase, and golang-migrate.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow and input carousel diagram. -->

## Quick start

```yaml
- uses: your-org/actions/db-migrate@v1
  with:
    database_url: ${{ secrets.DATABASE_URL }}
    migration_dir: migrations/
```

---

## How it works

```
inputs.database_url (masked immediately)
        │
        ▼
Validate inputs + mask secret
        │
        ▼
Health check — nc -z host:port (10 retries × 3s)
        │
        ▼
Install migration tool (flyway | liquibase | golang-migrate)
        │
        ▼
dry_run=true  → print pending migrations → stop
dry_run=false → acquire advisory lock → migrate up → release lock
        │
        ▼
verify_after=true → validate schema version
        │
        ▼
outputs.migrations_applied   (count of files applied)
outputs.current_version      (schema version after migration)
Job summary (always)
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `database_url` | string | **Yes** | **Yes** | — | Full connection URL — pass `${{ secrets.DATABASE_URL }}` |
| `migration_tool` | choice | No | No | `golang-migrate` | `flyway` / `liquibase` / `golang-migrate` |
| `migration_dir` | string | No | No | `migrations` | Directory containing migration files |
| `flyway_version` | string | No | No | `10.10.0` | Flyway version (when `migration_tool=flyway`) |
| `liquibase_version` | string | No | No | `4.27.0` | Liquibase version (when `migration_tool=liquibase`) |
| `golang_migrate_version` | string | No | No | `v4.17.1` | golang-migrate version |
| `dry_run` | boolean | No | No | `false` | Print pending migrations without applying |
| `verify_after` | boolean | No | No | `true` | Run post-migration schema verification |
| `lock_timeout_seconds` | string | No | No | `60` | Seconds to wait for migration lock |

---

## Outputs

| Output | Description |
|---|---|
| `migrations_applied` | Number of migration files applied |
| `current_version` | Schema version after migration |
| `dry_run_output` | Pending migrations list (dry_run=true only) |

---

## Variables and secrets

```yaml
# What is a secret:
# database_url — contains credentials (user:password@host) — MUST come from secrets store

# What is safe to log:
# migration_tool, migration_dir, dry_run, verify_after, versions — no credentials
```

The `database_url` is masked with `::add-mask::` in the **first line** of the first step. If it leaks in any tool output, it will be redacted.

```yaml
- uses: your-org/actions/db-migrate@v1
  with:
    database_url: ${{ secrets.DATABASE_URL }}       # secret
    migration_tool: golang-migrate                  # safe to hardcode
    migration_dir: db/migrations                    # safe to hardcode
```

Logged in job summary: tool, directory, dry-run flag, migrations applied, schema version.
Never logged: the database URL or any credential extracted from it.

---

## Permissions

```yaml
permissions:
  contents: read   # checkout only — no GitHub API calls
```

No `id-token: write` needed unless your database uses IAM authentication (pass the IAM token in the URL).

---

## Idempotency

**Idempotent** — all supported tools track applied migrations in a schema version table (`schema_migrations`, `flyway_schema_history`, or `DATABASECHANGELOG`). Re-running applies only pending migrations. Running with no pending migrations is a no-op.

---

## Concurrency — prevent parallel migration runs

Parallel migrations on the same database can corrupt schema state. Use a GitHub Actions concurrency group keyed on the database environment:

```yaml
concurrency:
  group: db-migrate-${{ inputs.environment }}
  cancel-in-progress: false   # never cancel a migration in progress
```

---

## Full example — deploy pipeline with pre-migration dry run

```yaml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  # Step 1 — dry run on PR to show what will change
  preview-migrations:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Preview pending migrations
        id: preview
        uses: your-org/actions/db-migrate@v1
        with:
          database_url: ${{ secrets.STAGING_DATABASE_URL }}
          migration_dir: db/migrations
          dry_run: 'true'

      - name: Post migration preview as PR comment
        uses: your-org/actions/pr-comment@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          title: 'Pending database migrations'
          body: |
            ```
            ${{ steps.preview.outputs.dry_run_output }}
            ```

  # Step 2 — apply on merge to main
  migrate-and-deploy:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    concurrency:
      group: db-migrate-production
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Run database migrations
        id: migrate
        uses: your-org/actions/db-migrate@v1
        with:
          database_url: ${{ secrets.PRODUCTION_DATABASE_URL }}
          migration_dir: db/migrations
          migration_tool: golang-migrate
          verify_after: 'true'
          lock_timeout_seconds: '120'

      - name: Deploy application
        run: |
          echo "Schema at version ${{ steps.migrate.outputs.current_version }}"
          echo "Applied ${{ steps.migrate.outputs.migrations_applied }} migrations"
          # ... deploy app after migrations succeed
```

---

## Rollback guidance

This action does not perform automatic rollback — migration rollback is inherently data-destructive and must be a deliberate choice.

For safe rollback:

```bash
# golang-migrate — roll back N steps
migrate -path db/migrations -database "$DATABASE_URL" down 1

# Flyway — undo the last applied migration (requires Flyway Teams or Enterprise)
flyway -url="$DATABASE_URL" undo

# Liquibase — roll back to a tagged version
liquibase rollback --tag=v1.2.3
```

Write reversible migrations where possible (add columns before removing old ones, create new tables before dropping old ones).

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
