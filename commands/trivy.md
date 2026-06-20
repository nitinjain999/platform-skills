---
name: trivy
description: Scan container images, filesystems, git repos, and existing SBOMs for CVEs, secrets, and license violations using Trivy. Covers local CLI, CI severity gates with SARIF upload, and continuous monitoring via Trivy Operator (Flux HelmRelease). Use when asked to "scan my image", "check for CVEs", "scan this repo for secrets", "scan an SBOM", or "set up continuous cluster vulnerability monitoring". IaC misconfig → /platform-skills:checkov. Admission posture → /platform-skills:kyverno. Image signing/SBOM generation → /platform-skills:supply-chain.
argument-hint: "[image|fs|repo|secrets|sbom|k8s] [target]"
---

Scan for vulnerabilities, secrets, and license violations — from local dev to running cluster.

Read `references/trivy.md` before responding. It contains all mode logic, bootstrap steps, severity gating, output formats, `.trivyignore` patterns, and the Trivy Operator install via Flux HelmRelease.

## Ownership boundary (enforced at the menu)

| Question | Authoritative command |
|---|---|
| "Is there a misconfig in my Terraform?" | `/platform-skills:checkov` |
| "Will this manifest pass admission?" | `/platform-skills:kyverno apply` |
| "How do I sign my image / generate an SBOM?" | `/platform-skills:supply-chain` |
| "Is this image safe to ship?" | **this command** |
| "Are there secrets in this repo?" | **this command** |
| "What CVEs are running in my cluster?" | **this command** (`k8s` / Operator) |

---

## Mode dispatch

Parse the first word of `$ARGUMENTS` as the mode. When `$ARGUMENTS` is empty, run the three-layer interactive wizard.

| Mode | What it does |
|---|---|
| `image` | Scan a container image for OS and library CVEs |
| `fs` | Scan a local directory for CVEs, secrets, and license violations |
| `repo` | Scan a remote git repo URL (same as `fs` but clones first) |
| `secrets` | Scan current repo for hardcoded secrets only (`--scanners secret`) |
| `sbom` | Scan an existing Syft-generated SBOM file (`trivy sbom <file>`) |
| `k8s` | Live cluster image-CVE scanning via Trivy Operator (Flux HelmRelease) |
| _(empty)_ | Three-layer interactive wizard |

---

## Three-layer interactive wizard

### Layer 1 — Developer question (intent in their language)

```
What are you trying to find out?
  1. "Is this image safe to ship?"              → image CVE scan
  2. "Are there secrets in this repo/code?"      → secret scan
  3. "What's the full risk of this checkout?"    → fs scan (vuln + secret + license)
  4. "What's running vulnerable in my cluster?"  → live cluster scan (Operator)
  5. "Is this SBOM vulnerable?"                  → SBOM scan (Syft output)

  IaC misconfig?              → /platform-skills:checkov
  Will this manifest pass admission? → /platform-skills:kyverno apply
  Image signing / SBOM generation?   → /platform-skills:supply-chain

Enter 1–5 or mode name:
```

### Layer 2 — End goal (decides execution shape)

```
What do you want out of it?
  a. A quick answer right now        → CLI one-shot, table output
  b. A pass/fail gate in CI          → exit-code gate + SARIF upload to code scanning
  c. Continuous monitoring           → Trivy Operator via Flux HelmRelease (cluster only)

Enter a, b, or c:
```

### Layer 3 — Concerns (surface trade-offs; ask only where a wrong default causes harm)

```
A few quick settings (press Enter to accept the recommended value):

  • Severity floor [HIGH,CRITICAL]: CRITICAL-only is quieter but misses HIGH exploitables.
    Recommended: HIGH,CRITICAL — enter to accept or type CRITICAL to narrow.

  • --ignore-unfixed [off]: suppresses CVEs with no upstream fix — cuts noise but hides
    un-patchable risk. Enter to keep off, or type 'on' to enable.

  • .trivyignore: every CVE you suppress needs an expiry date and justification, or the
    gate rots silently. Want a template .trivyignore with expiry headers? [y/N]
```

Detected-only prompts (ask silently, only if needed):
- Private registry credentials: if the image ref contains a private host, ask for `TRIVY_USERNAME` / `TRIVY_PASSWORD` or registry token.
- Large image warning: if `docker inspect` shows > 2 GB, warn before pulling.

Do not pepper with questions. Only prompt where getting it wrong causes real harm.

---

## Mode: image

Scan a container image for OS package and library CVEs.

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --format table \
  [--ignore-unfixed] \
  <image-ref>
```

Reference: `references/trivy.md` → Mode: image — bootstrap, auth, output formats, SARIF, .trivyignore

---

## Mode: fs

Scan a local filesystem directory for CVEs, secrets, and license violations in one pass.

```bash
trivy fs \
  --scanners vuln,secret,license \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  .
```

Reference: `references/trivy.md` → Mode: fs

---

## Mode: repo

Scan a remote git repo URL (Trivy clones internally; no local clone needed).

```bash
trivy repo \
  --scanners vuln,secret,license \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  https://github.com/<org>/<repo>
```

Reference: `references/trivy.md` → Mode: repo

---

## Mode: secrets

Scan for hardcoded secrets only (API keys, tokens, credentials) across the entire repo.

```bash
trivy fs \
  --scanners secret \
  --exit-code 1 \
  .
```

Reference: `references/trivy.md` → Mode: secrets — secret rule sets, .trivyignore for false positives

---

## Mode: sbom

Scan an existing Syft-generated SBOM file (CycloneDX or SPDX) for known CVEs.
Trivy does not generate SBOMs here — generation is owned by `/platform-skills:supply-chain` (Syft + Cosign attest).

```bash
trivy sbom \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  sbom.spdx.json
```

Reference: `references/trivy.md` → Mode: sbom

---

## Mode: k8s

Continuous image-CVE monitoring across all cluster workloads via Trivy Operator, deployed through Flux HelmRelease.
This mode is NOT manifest posture scanning — that is owned by `/platform-skills:kyverno apply`.

```bash
# One-shot cluster scan (requires kubectl context)
trivy k8s --report summary cluster
```

For continuous monitoring, deploy the Trivy Operator via Flux HelmRelease.
Reference: `references/trivy.md` → Mode: k8s — Trivy Operator Flux HelmRelease, VulnerabilityReport CRDs, Prometheus metrics

---

## Agent behavior

### Intent classification

Before asking any question, classify from the user's free-text request:

| Intent signals | Mode |
|---|---|
| "scan image", "check image", "CVEs in image", "safe to ship", "image vulnerabilities" | `image` |
| "scan this directory", "scan this code", "full risk", "local scan" | `fs` |
| "scan this repo", "scan github.com/", "remote repo" | `repo` |
| "secrets in code", "hardcoded token", "leaked key", "credentials in repo" | `secrets` |
| "scan sbom", "sbom vulnerabilities", "check syft output", "sbom file" | `sbom` |
| "cluster CVEs", "running vulnerabilities", "trivy operator", "continuous monitoring" | `k8s` |
| "terraform misconfig", "IaC security", "checkov" | → hand off to `/platform-skills:checkov` |
| "manifest admission", "kyverno policy", "will this manifest pass" | → hand off to `/platform-skills:kyverno` |
| "sign image", "generate sbom", "slsa", "cosign" | → hand off to `/platform-skills:supply-chain` |

### Ask only for missing high-risk inputs

| When to ask | Question |
|---|---|
| `image` mode, image ref not provided | "Which image? (e.g. ghcr.io/org/image:tag or digest)" |
| `sbom` mode, file path not provided | "Path to the SBOM file? (e.g. sbom.spdx.json)" |
| `k8s` mode, goal (b) vs (c) not clear | "CI one-shot scan or deploy the Trivy Operator for continuous monitoring?" |
| Private registry detected | "Registry credentials? Set TRIVY_USERNAME and TRIVY_PASSWORD, or provide a token." |
| `.trivyignore` has entries without expiry | "These suppressions have no expiry date — add one? (y/N)" |

Never ask about: output format (default table for CLI, sarif for CI), whether to bootstrap (always do it), or whether to add `.trivyignore` to `.gitignore` (always do it).

---

## Cross-references

- `/platform-skills:checkov` — IaC source and plan-level security scanning (Terraform, GHA, Helm)
- `/platform-skills:kyverno` — Kubernetes admission policy; `kyverno apply` for manifest posture scanning
- `/platform-skills:supply-chain` — image signing (Cosign), SBOM generation and attestation (Syft), SLSA provenance
- `/platform-skills:runtime-security` — Falco syscall-level threat detection (complements CVE scanning)
