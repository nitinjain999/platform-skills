# Trivy Reference

Covers all `/platform-skills:trivy` mode logic: bootstrap, per-mode execution, severity gating, output formats, `.trivyignore` / `trivy.yaml` config, private-registry auth, and the Trivy Operator via Flux HelmRelease.

---

## Tool Ownership Boundary

| Concern | Authoritative tool |
|---|---|
| Container image CVEs | **Trivy** |
| Filesystem / repo scan (vuln + secret + license) | **Trivy** |
| Secret scanning | **Trivy** |
| SBOM vulnerability scanning | **Trivy** (`trivy sbom`) |
| Live cluster image CVEs (continuous) | **Trivy Operator** |
| IaC misconfig (Terraform, GHA, Helm) | Checkov → `/platform-skills:checkov` |
| K8s manifest admission posture | Kyverno CLI → `/platform-skills:kyverno` |
| SBOM generation + attestation | Syft + Cosign → `/platform-skills:supply-chain` |
| Image signing / SLSA | Cosign → `/platform-skills:supply-chain` |

---

## Bootstrap

### macOS

```bash
brew install aquasecurity/trivy/trivy
trivy --version   # expect >= 0.50.0
```

### Linux (binary)

```bash
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /usr/local/bin
trivy --version
```

### CI (GitHub Actions)

```yaml
- name: Install Trivy
  run: |
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin
```

Or use the official action (pinned to SHA):

```yaml
- uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25  # v0.36.0
```

### Minimum version guard

```bash
MIN_VERSION="0.50.0"
CURRENT=$(trivy --version | awk '/Version:/{print $2}')
# sort -V is GNU-only; use dot-field integer comparison for macOS/Linux portability
version_gte() {
  local IFS=. a b
  read -ra a <<< "$1"; read -ra b <<< "$2"
  for i in 0 1 2; do
    local av=${a[$i]:-0} bv=${b[$i]:-0}
    (( av > bv )) && return 0; (( av < bv )) && return 1
  done
  return 0  # versions are equal — guard passes
}
if ! version_gte "$CURRENT" "$MIN_VERSION"; then
  echo "ERROR: trivy >= $MIN_VERSION required (found $CURRENT)" >&2
  exit 1
fi
```

---

## Mode: image

Scan a container image for OS package and library CVEs.

### One-shot (CLI)

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --format table \
  ghcr.io/org/image:tag
```

### CI severity gate (exit-code 1 = fail build)

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --format sarif \
  --output trivy-results.sarif \
  ghcr.io/org/image:tag
```

### Full GitHub Actions job

```yaml
jobs:
  trivy-scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write   # upload SARIF to code scanning
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Run Trivy image scan
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25  # v0.36.0
        with:
          image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
          format: sarif
          output: trivy-results.sarif
          exit-code: '1'
          ignore-unfixed: false
          vuln-type: os,library
          severity: HIGH,CRITICAL

      - name: Upload SARIF to GitHub Security tab
        if: always()
        uses: github/codeql-action/upload-sarif@f411752efdf656cb71aa17b755b22c890960da1d  # v3.35.5
        with:
          sarif_file: trivy-results.sarif
```

### Private registry auth

```bash
# GHCR
export TRIVY_USERNAME=<github-user>
export TRIVY_PASSWORD=$(gh auth token)

# ECR (uses ambient IRSA / instance profile — no creds needed in CI with IRSA)
# Or explicit:
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
trivy image --aws-region eu-north-1 <account-id>.dkr.ecr.eu-north-1.amazonaws.com/image:tag

# Generic registry
trivy image --username $USER --password $PASS registry.example.com/image:tag
```

---

## Mode: fs

Scan a local directory for CVEs, secrets, and license violations in one pass.

```bash
trivy fs \
  --scanners vuln,secret,license \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  .
```

### Scanners available

| Scanner | Finds |
|---|---|
| `vuln` | CVEs in package manifests (go.sum, package-lock.json, requirements.txt, etc.) |
| `secret` | Hardcoded credentials, API keys, tokens |
| `license` | License violations (GPL in commercial code, etc.) |

### Disable specific scanners

```bash
# Vulnerability only — skip secret/license in quick checks
trivy fs --scanners vuln --severity HIGH,CRITICAL .
```

---

## Mode: repo

Scan a remote git repo URL. Trivy clones it internally; no local checkout needed.

```bash
trivy repo \
  --scanners vuln,secret,license \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  https://github.com/org/repo
```

### Private repo auth

```bash
export TRIVY_GITHUB_TOKEN=$(gh auth token)
trivy repo https://github.com/org/private-repo
```

---

## Mode: secrets

Scan for hardcoded secrets only (fastest single-concern scan).

```bash
trivy fs \
  --scanners secret \
  --exit-code 1 \
  .
```

### Suppress known false positives

```bash
# .trivyignore — see .trivyignore section below
# Or inline:
trivy fs --scanners secret --ignorefile .trivyignore .
```

### Secret rule sets

Trivy ships built-in rules for: AWS keys, GCP service accounts, GitHub tokens, Stripe, Slack, SendGrid, private keys (RSA/EC/DSA/PGP), connection strings, and more. Custom rules via `trivy.yaml`:

```yaml
# trivy.yaml
secret:
  config: custom-secret-rules.yaml
```

---

## Mode: sbom

Scan an existing Syft-generated SBOM file for known CVEs.
**Do not use Trivy to generate SBOMs** — that is owned by Syft via `/platform-skills:supply-chain`.

```bash
# CycloneDX JSON
trivy sbom \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  sbom.cdx.json

# SPDX JSON
trivy sbom \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  sbom.spdx.json
```

### SBOM vulnerability gate in CI

```yaml
- name: Scan SBOM for CVEs
  run: |
    trivy sbom \
      --severity HIGH,CRITICAL \
      --format sarif \
      --output trivy-sbom.sarif \
      --exit-code 1 \
      sbom.spdx.json

- name: Upload SBOM scan results
  if: always()
  uses: github/codeql-action/upload-sarif@f411752efdf656cb71aa17b755b22c890960da1d  # v3.35.5
  with:
    sarif_file: trivy-sbom.sarif
```

---

## Mode: k8s

### One-shot cluster scan (requires kubectl context)

```bash
# Summary of all workloads
trivy k8s --report summary cluster

# Full detail — slow on large clusters
trivy k8s --report all cluster

# Scope to a single namespace
trivy k8s --report summary --namespace production cluster
```

This scans images referenced in running pods — it is NOT manifest posture scanning. For manifest posture (does this manifest satisfy Kyverno policies?), use `/platform-skills:kyverno apply`.

### Trivy Operator — continuous monitoring via Flux HelmRelease

Trivy Operator runs as a Kubernetes controller and continuously scans all workload images, producing `VulnerabilityReport` and `ExposedSecretReport` CRDs per pod.

#### Flux HelmRelease

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: aquasecurity
  namespace: flux-system
spec:
  interval: 24h
  url: https://aquasecurity.github.io/helm-charts/
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: trivy-operator
  namespace: trivy-system
spec:
  interval: 1h
  install:
    strategy:
      name: RetryOnFailure   # retry without uninstall/rollback on failure
  upgrade:
    strategy:
      name: RetryOnFailure
  chart:
    spec:
      chart: trivy-operator
      version: "0.33.2"
      sourceRef:
        kind: HelmRepository
        name: aquasecurity
        namespace: flux-system
  values:
    trivy:
      ignoreUnfixed: false
      severity: HIGH,CRITICAL
    serviceMonitor:
      enabled: true    # expose Prometheus metrics
    operator:
      scanJobTimeout: 5m
      # Scope to specific namespaces (omit to scan all)
      # targetNamespaces: "production,staging"
```

#### Query VulnerabilityReports

```bash
# List all reports
kubectl get vulnerabilityreports -A

# Show a specific workload's CVEs
kubectl get vulnerabilityreport -n production \
  replicaset-app-deployment-abc123 -o yaml

# Count CRITICAL/HIGH across the cluster
kubectl get vulnerabilityreports -A -o json \
  | jq '[.items[].report.summary | (.criticalCount + .highCount)] | add'
```

#### Prometheus metrics (if serviceMonitor enabled)

```promql
# Total CRITICAL CVEs across cluster
sum(trivy_image_vulnerabilities{severity="CRITICAL"})

# Images with any CRITICAL vulnerability
count(trivy_image_vulnerabilities{severity="CRITICAL"} > 0)
```

---

## Severity gating

### Recommended defaults

| Gate | Severity floor | `--ignore-unfixed` | Notes |
|---|---|---|---|
| CI severity gate (block PRs) | `HIGH,CRITICAL` | `false` | Standard — catches exploitables |
| Quick local check | `HIGH,CRITICAL` | `false` | Same as CI for consistency |
| Noisy baseline (brownfield) | `CRITICAL` | `true` | Narrow gate to get started; widen over time |
| License audit | any | N/A | Use `--scanners license` |

**Do not use `CRITICAL` only as a permanent gate.** HIGH CVEs include actively exploited issues (e.g. Log4Shell was initially scored HIGH before CVSS updates).

### Exit codes

| Code | Meaning |
|---|---|
| `0` | No vulnerabilities at or above severity floor |
| `1` | Vulnerabilities found at or above severity floor |
| `2` | Scan error (image not found, auth failure) |

Always check for exit code `2` in CI — a failed scan should not silently pass.

```bash
trivy image --exit-code 1 myimage:latest
rc=$?
if [ $rc -eq 2 ]; then
  echo "ERROR: Trivy scan failed (auth? network?)" >&2
  exit 2
fi
exit $rc
```

---

## Output formats

| Format | Flag | Use case |
|---|---|---|
| Table | `--format table` | Human-readable terminal output |
| JSON | `--format json --output trivy.json` | Downstream processing, dashboards |
| SARIF | `--format sarif --output trivy.sarif` | GitHub Security tab (code scanning) |
| CycloneDX | `--format cyclonedx --output trivy.cdx.json` | SBOM-style output (not recommended — use Syft) |
| GitHub | `--format github` | GitHub dependency graph |

---

## `.trivyignore` — CVE suppression policy

Every suppressed CVE must have:
1. The CVE ID
2. An expiry date
3. A justification

A `.trivyignore` without expiry dates rots silently — the gate becomes meaningless.

```
# .trivyignore
# Format: <CVE-ID> [exp:<YYYY-MM-DD>] [# justification]

CVE-2024-12345 exp:2026-09-01  # OS base-image, no upstream fix yet — review at next base image bump
CVE-2024-67890 exp:2026-07-01  # false positive: internal tool, never exposed to untrusted input
CVE-2025-11111 exp:2026-08-01  # Go stdlib, binary statically linked, not affected by this vector
```

### Detect expired suppressions

```bash
TODAY=$(date +%Y-%m-%d)
while IFS= read -r line; do
  # sed -E is portable (macOS + Linux); grep -oP requires GNU grep
  exp=$(echo "$line" | sed -E 's/.*exp:([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/; t; d')
  if [[ -n "$exp" && "$exp" < "$TODAY" ]]; then
    echo "EXPIRED: $line"
  fi
done < .trivyignore
```

---

## `trivy.yaml` — persistent config

```yaml
# trivy.yaml (at repo root or $XDG_CONFIG_HOME/trivy/trivy.yaml)
scan:
  scanners:
    - vuln
    - secret
severity:
  - HIGH
  - CRITICAL
ignore-unfixed: false
ignorefile: .trivyignore
format: table
exit-code: 1
```

---

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| `--exit-code 0` (default) in CI | Gate never fails — silent | Always set `--exit-code 1` |
| `--severity CRITICAL` only | Misses HIGH exploitables | Use `HIGH,CRITICAL` |
| `trivy config` on `.tf` files | Duplicates Checkov; divergent findings | Use Checkov for IaC |
| `trivy image --generate-sbom` | Creates un-attested SBOM; drifts from Syft | Use Syft + Cosign attest |
| `.trivyignore` with no expiry | Suppressions accumulate silently | Enforce exp: dates |
| Scanning manifest files for posture | Reimplements Kyverno rules; diverges | Use `kyverno apply` |
| Not checking exit code 2 | Auth/network failure silently passes | Explicitly check `$?` for `2` |
| `ignore-unfixed: true` as permanent default | Hides un-patchable risk | Use only for brownfield baseline |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `FATAL image pull failed` | Registry auth missing | Set `TRIVY_USERNAME` / `TRIVY_PASSWORD` or `TRIVY_GITHUB_TOKEN` |
| `FATAL failed to analyze` | Corrupted layer cache | `trivy image --clear-cache` then re-run |
| `database download failed` | Network / proxy blocks `ghcr.io` | Set `TRIVY_DB_REPOSITORY` to a mirror, or use `--offline-scan` with pre-downloaded DB |
| Scan very slow on large images | Full image pull | Use `--skip-dirs` to exclude known-clean paths, or scope with `--image-config-scanners` |
| False-positive secrets | Test fixtures, example files | Add to `.trivyignore` with expiry and justification |
| VulnerabilityReport CRDs empty after Operator install | Operator not yet reconciled | `kubectl rollout status deploy/trivy-operator -n trivy-system`; check `kubectl logs` |

---

## Cross-references

- `commands/trivy.md` — interactive command (wizard, mode dispatch, agent behavior)
- `references/supply-chain.md` — Cosign image signing, Syft SBOM generation, SLSA provenance
- `references/kyverno.md` — Kyverno admission policies, `kyverno apply` for manifest posture
- `references/checkov.md` — Checkov IaC scanning (Terraform, GHA, Helm)
- `references/runtime-security.md` — Falco for syscall-level threat detection at runtime
- `examples/supply-chain/trivy-image-scan.sh` — production-ready image scan CI script
