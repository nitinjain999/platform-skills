# docker-build-push

> Build a multi-platform Docker image and push it to GHCR using OIDC. No long-lived credentials required.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow, lifecycle loop, and input carousel diagram. -->

## Quick start

```yaml
- uses: your-org/actions/docker-build-push@v1
  with:
    image_name: my-service
```

The caller workflow must have `packages: write` and `id-token: write` permissions.

---

## Architecture

```
Developer push / PR merge
        │
        ▼
┌─────────────────────────────────────────────────────┐
│  docker-build-push composite action                  │
│                                                      │
│  1. Validate inputs                                  │
│  2. Compute short tag (first 7 chars of SHA)         │
│  3. Set up QEMU + Docker Buildx                      │
│  4. Login to GHCR via GITHUB_TOKEN (ephemeral)       │
│  5. Extract metadata (tags, labels)                  │
│  6. Build → push (multi-platform, GHA cache)         │
│     + SLSA provenance + SBOM attestations            │
│  7. Write job summary                                │
└─────────────────────────────────────────────────────┘
        │
        ▼
ghcr.io/org/my-service:<short-sha>
ghcr.io/org/my-service:latest   (main branch only)
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `image_name` | string | **Yes** | No | — | Image name (e.g. `my-service`) |
| `image_tag` | string | No | No | `${{ github.sha }}` | Full tag; action uses first 7 chars |
| `platforms` | string | No | No | `linux/amd64` | Comma-separated platforms |
| `context` | string | No | No | `.` | Docker build context path |
| `dockerfile` | string | No | No | `Dockerfile` | Path to Dockerfile |
| `build_args` | string | No | No | `''` | Newline-separated `KEY=VALUE` args |
| `push` | boolean | No | No | `true` | Push after build |
| `registry` | string | No | No | `ghcr.io` | Registry host |

---

## Outputs

| Output | Description |
|---|---|
| `image_uri` | Full image URI including tag |
| `image_digest` | SHA256 digest of the published image |
| `image_tag` | Short 7-character tag |

---

## Variables and secrets

This action uses **only ephemeral credentials** — no secrets are required.

```yaml
# What flows in:
# GITHUB_TOKEN (ephemeral, auto-rotated) ──► docker/login-action
#                                              ↳ authenticates to ghcr.io
#
# github.sha (workflow context) ──► image_tag (plain variable — safe to log)
# inputs.image_name ──► plain variable — safe to log and hardcode
```

**Build arguments and secrets:**

Do not pass secrets via `build_args` — they appear in image history. Use Docker BuildKit secrets instead:

```yaml
# ❌ Secret leaks into image layer history
build_args: |
  DB_PASSWORD=supersecret

# ✅ BuildKit secret mount — not stored in image
# In your Dockerfile:
# RUN --mount=type=secret,id=db_pass DB_PASS=$(cat /run/secrets/db_pass) ...
# In your workflow (before calling this action):
- name: Build with secret
  run: |
    docker buildx build \
      --secret id=db_pass,env=DB_PASSWORD \
      -t myapp .
  env:
    DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
```

---

## Permissions

```yaml
permissions:
  contents: read
  packages: write    # push to GHCR
  id-token: write    # OIDC token for future Cosign signing
```

---

## Idempotency

**Safe to re-run.** If the same commit SHA is pushed twice, the image tag is identical and the registry push is a no-op (digest unchanged). The GHA layer cache (`type=gha`) further accelerates repeated builds.

---

## Concurrency (recommended)

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true   # cancel old build when new commit arrives
```

---

## Full example

```yaml
name: Build and push

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  packages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest

    concurrency:
      group: ${{ github.workflow }}-${{ github.ref }}
      cancel-in-progress: true

    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Build and push
        id: build
        uses: your-org/actions/docker-build-push@v1
        with:
          image_name: my-service
          platforms: linux/amd64,linux/arm64

      - name: Print image URI
        run: echo "Published ${{ steps.build.outputs.image_uri }}"
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
