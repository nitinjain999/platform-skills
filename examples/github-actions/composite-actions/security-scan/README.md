# security-scan

> Scan a container image or filesystem with Trivy. Posts annotations for CRITICAL and HIGH findings, writes a job summary, and optionally fails the workflow when vulnerabilities are found.

Status: Stable

<!-- Run `/platform-skills:awesome-docs generate` on this file to add an animated architecture flow diagram. -->

## Quick start

```yaml
- uses: your-org/actions/security-scan@v1
  with:
    scan_target: ghcr.io/org/my-service:${{ github.sha }}
```

---

## Inputs

| Input | Type | Required | Secret | Default | Description |
|---|---|---|---|---|---|
| `scan_target` | string | **Yes** | No | — | Image URI or path to scan |
| `scan_type` | choice | No | No | `image` | `image` / `fs` / `repo` |
| `severity` | string | No | No | `HIGH,CRITICAL` | Severity levels to report |
| `fail_on_findings` | boolean | No | No | `true` | Fail when findings found |
| `ignore_unfixed` | boolean | No | No | `false` | Skip findings with no fix |
| `trivy_version` | string | No | No | `0.58.0` | Trivy version to install |
| `output_format` | choice | No | No | `table` | `table` / `json` / `sarif` |
| `registry_username` | string | No | No | `''` | Registry username (private images) |
| `registry_password` | string | No | **Yes** | `''` | Registry password — pass from secrets |

---

## Outputs

| Output | Description |
|---|---|
| `vulnerability_count` | Total findings at or above severity threshold |
| `scan_result` | `pass` or `fail` |
| `sarif_path` | Path to SARIF file (when `output_format: sarif`) |

---

## Variables and secrets

Only `registry_password` is a secret and only needed for private registries:

```yaml
# Public image or GHCR via GITHUB_TOKEN — no credentials needed
- uses: your-org/actions/security-scan@v1
  with:
    scan_target: ghcr.io/org/my-service:latest

# Private registry
- uses: your-org/actions/security-scan@v1
  with:
    scan_target: registry.example.com/org/service:latest
    registry_username: robot-scanner
    registry_password: ${{ secrets.REGISTRY_PASSWORD }}   # SECRET
```

---

## Permissions

```yaml
permissions:
  contents: read
  security-events: write   # upload SARIF to GitHub Code Scanning (when output_format: sarif)
```

---

## Idempotency

**Idempotent** — scanning the same image twice produces the same findings. Safe to re-run.

---

## Full example — scan after build, gate before deploy

```yaml
name: Build, scan, deploy

on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write
  id-token: write
  security-events: write

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image_uri: ${{ steps.build.outputs.image_uri }}
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - id: build
        uses: your-org/actions/docker-build-push@v1
        with:
          image_name: my-service

  scan:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - uses: your-org/actions/security-scan@v1
        with:
          scan_target: ${{ needs.build.outputs.image_uri }}
          severity: HIGH,CRITICAL
          fail_on_findings: true

  deploy:
    runs-on: ubuntu-latest
    needs: [build, scan]   # only runs if scan passes
    steps:
      - uses: your-org/actions/k8s-deploy@v1
        with:
          kubeconfig: ${{ secrets.KUBECONFIG }}
          namespace: production
          manifest_path: deploy/
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md)
