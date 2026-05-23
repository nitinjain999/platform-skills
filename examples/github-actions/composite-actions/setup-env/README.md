# setup-env

> Install a language runtime (Node.js, Python, or Go) and restore the dependency cache in a single `uses:` call. Based on the official GitHub Docs composite action tutorial — extended with multi-runtime support, input validation, and job summary.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow and input carousel diagram. -->

## Quick start

```yaml
# Node.js
- uses: your-org/actions/setup-env@v1
  with:
    runtime: node

# Python
- uses: your-org/actions/setup-env@v1
  with:
    runtime: python
    version: '3.12'

# Go
- uses: your-org/actions/setup-env@v1
  with:
    runtime: go
    version: '1.22.x'
```

---

## How it works

```
inputs.runtime (node | python | go)
        │
        ▼
Resolve version (use inputs.version or default per runtime)
        │
        ├── node   → actions/setup-node → ~/.npm cache → npm ci
        ├── python → actions/setup-python → ~/.cache/pip cache → pip install
        └── go     → actions/setup-go → ~/go/pkg/mod cache → go mod download
        │
        ▼
outputs.runtime_version (exact installed version)
outputs.cache_hit        (true | false)
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `runtime` | choice | **Yes** | No | — | `node` / `python` / `go` |
| `version` | string | No | No | Runtime default | Version to install (e.g. `20.x`, `3.12`, `1.22.x`) |
| `enable_cache` | boolean | No | No | `true` | Restore dependency cache |
| `working_directory` | string | No | No | `.` | Directory with lock file |
| `install_dependencies` | boolean | No | No | `true` | Run install after setup |

**Runtime version defaults:**

| Runtime | Default version |
|---|---|
| node | `20.x` |
| python | `3.12` |
| go | `1.22.x` |

---

## Outputs

| Output | Description |
|---|---|
| `runtime_version` | Exact installed runtime version |
| `cache_hit` | `true` if the dependency cache was restored |

---

## Variables and secrets

No secrets required. All inputs are plain variables.

```yaml
# What flows in (all safe to log):
# inputs.runtime   → 'node', 'python', or 'go'
# inputs.version   → '20.x', '3.12', etc.
#
# Cache keys are derived from lock file hashes — never contain credentials
```

---

## Permissions

```yaml
permissions:
  contents: read   # checkout only
```

---

## Idempotency

**Idempotent** — running twice restores the same cache (or rebuilds it if the lock file changed). The setup tools are also idempotent.

---

## Full example — matrix across runtimes

```yaml
name: Multi-runtime CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - runtime: node
            version: '20.x'
          - runtime: node
            version: '22.x'
          - runtime: python
            version: '3.12'
          - runtime: go
            version: '1.22.x'

    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Setup ${{ matrix.runtime }} ${{ matrix.version }}
        id: setup
        uses: your-org/actions/setup-env@v1
        with:
          runtime: ${{ matrix.runtime }}
          version: ${{ matrix.version }}

      - name: Print installed version
        run: echo "Installed ${{ matrix.runtime }} ${{ steps.setup.outputs.runtime_version }}"

      - name: Run tests (node)
        if: matrix.runtime == 'node'
        run: npm test

      - name: Run tests (python)
        if: matrix.runtime == 'python'
        run: python -m pytest

      - name: Run tests (go)
        if: matrix.runtime == 'go'
        run: go test ./...
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
