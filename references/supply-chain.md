---
title: Supply Chain Security
custom_edit_url: null
---

# Supply Chain Security Reference

Covers the full supply chain security stack: keyless image signing with Cosign, SBOM generation and attestation with Syft, CVE scanning with Trivy/Grype, SLSA Level 2 provenance, and Kyverno admission enforcement. All tools are open-source with no license cost.

---

## Tool Stack

| Tool | Purpose | Project |
|---|---|---|
| Cosign (Sigstore) | Keyless image signing and verification | CNCF (Sigstore) |
| Fulcio | Certificate authority for keyless signing | CNCF (Sigstore) |
| Rekor | Transparency log for signatures and attestations | CNCF (Sigstore) |
| Syft | SBOM generation (SPDX, CycloneDX) | Anchore OSS |
| Trivy | CVE scanning, SBOM, misconfiguration detection | CNCF (Aqua) |
| Grype | CVE scanning against Syft SBOM | Anchore OSS |
| slsa-github-generator | SLSA Level 2/3 provenance via GitHub Actions | OpenSSF |
| Kyverno ImageValidatingPolicy | Admission enforcement for signed images | CNCF |

---

## Keyless Signing with Cosign

Keyless signing uses GitHub Actions OIDC tokens — no private key to store, rotate, or leak.

### Flow

```
GitHub Actions OIDC token
  → Fulcio CA (issues short-lived signing certificate)
  → Cosign signs image digest with that certificate
  → Signature + certificate uploaded to Rekor transparency log
```

### Sign in CI

```yaml
# Job-level permissions required for keyless signing
permissions:
  id-token: write   # required for Cosign OIDC token exchange with Fulcio
  packages: write   # required to push to GHCR

- name: Install Cosign
  uses: sigstore/cosign-installer@11086d9f32b178aa24e93c2b86eba3ef4b16b68a  # v3.8.1

- name: Sign image
  run: |
    cosign sign --yes \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
```

**Always sign the digest, not the tag.** Tags are mutable; a digest is immutable.

### Verify locally

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/<org>/<repo>/.github/workflows/.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/<org>/<image>@<digest>
```

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `no matching signatures` | Image was pushed without signing step | Run the sign step after push, not before |
| `certificate has expired` | Short-lived cert checked too late | Re-sign; keyless certs are valid for ~10 min |
| `COSIGN_EXPERIMENTAL set in CI` | Leftover cosign v1 config | Remove it; keyless is the default in cosign v2 |

---

## SBOM Generation and Attestation with Syft

An SBOM (Software Bill of Materials) lists every package inside the image. Attesting it as an OCI artifact links the SBOM to the specific image digest in Rekor.

### Generate and attest

```yaml
# Job-level permissions required for cosign attest
permissions:
  id-token: write   # required for Cosign OIDC token exchange with Fulcio
  packages: write   # required to push attestation to GHCR

- name: Generate SBOM
  uses: anchore/sbom-action@61119d458adab75f756bc0b9e4bde25725f86a7a  # v0.20.0
  with:
    image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
    format: spdx-json
    output-file: sbom.spdx.json

- name: Attest SBOM
  run: |
    cosign attest --yes \
      --predicate sbom.spdx.json \
      --type spdxjson \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
```

### SBOM formats

| Format | Use case |
|---|---|
| `spdx-json` | Broadest tooling support; recommended default |
| `cyclonedx-json` | Better for dependency tracking; preferred by some scanners |

### Retrieve SBOM attestation

```bash
cosign download attestation \
  --predicate-type https://spdx.dev/Document \
  ghcr.io/<org>/<image>@<digest> \
  | jq '.payload | @base64d | fromjson'
```

---

## Vulnerability Scanning: Trivy vs Grype

Both tools scan container images for CVEs. Use Trivy for new setups; use Grype if already using Syft in the pipeline.

### Trivy (recommended)

```yaml
- name: Scan image
  uses: aquasecurity/trivy-action@18f2135c0b15d26b3a4c2efded75e06b6f0e4884  # v0.30.0
  with:
    image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
    format: table
    exit-code: '1'
    ignore-unfixed: true
    vuln-type: os,library
    severity: CRITICAL,HIGH
```

`ignore-unfixed: true` suppresses CVEs with no available fix — they cannot be actioned, and suppressing them reduces noise without weakening the gate.

### Grype (Anchore)

```yaml
- name: Scan with Grype
  uses: anchore/scan-action@16910d14a7731ecfd3ac9785e39a479f53cca83c  # v3.9.0
  with:
    image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
    fail-build: true
    severity-cutoff: high
```

### Severity gate strategy

| Gate | What it catches | Recommended for |
|---|---|---|
| `CRITICAL` only | Actively exploited, widely known | Minimum viable gate |
| `CRITICAL,HIGH` | High-impact CVEs with known exploit paths | **Recommended default** |
| `CRITICAL,HIGH,MEDIUM` | Broad coverage | Regulated environments |

---

## SLSA Level 2 Provenance

SLSA (Supply-chain Levels for Software Artifacts) Level 2 provides a signed attestation linking the artifact to the exact build inputs: source commit, workflow, and runner.

### What each level requires

| Level | Requirement |
|---|---|
| L1 | Provenance generated (unsigned) |
| **L2** | Provenance signed by CI; hosted build platform |
| L3 | Hardened builds; hermetic; no secret injection |

**L2 is achievable on standard GitHub-hosted runners. L3 requires hermetic builds (not available on standard runners).**

### Workflow (slsa-github-generator)

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.build.outputs.digest }}
    permissions:
      contents: read
      packages: write
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - name: Build and push
        id: build
        uses: docker/build-push-action@48aba3b46d1b1fec4febb7c5d0c644b249a11355  # v6.10.0
        with:
          push: true
          tags: ghcr.io/<org>/<image>:${{ github.sha }}

  provenance:
    needs: build
    permissions:
      actions: read
      id-token: write
      packages: write
    uses: slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@5a775b367a56d5bd118a224a811bba288150a563  # v2.0.0
    # Pin to a specific release SHA for production. Get SHA via:
    # gh api repos/slsa-framework/slsa-github-generator/git/ref/tags/v2.0.0
    with:
      image: ghcr.io/<org>/<image>
      digest: ${{ needs.build.outputs.digest }}
      registry-username: ${{ github.actor }}
    secrets:
      registry-password: ${{ secrets.GITHUB_TOKEN }}
```

### Verify provenance

```bash
slsa-verifier verify-image \
  ghcr.io/<org>/<image>@<digest> \
  --source-uri github.com/<org>/<repo> \
  --source-branch main
```

---

## Kyverno Admission Enforcement

Block unsigned or unverified images at the Kubernetes admission layer using `ImageValidatingPolicy`.

### Keyless policy (Sigstore)

```yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: require-signed-images
  annotations:
    policies.kyverno.io/title: Require Signed Images
    policies.kyverno.io/description: >
      Block admission of images not signed via Sigstore keyless signing from GitHub Actions.
      Apply to selected namespaces using matchConditions.
spec:
  validationActions: [Audit]   # switch to [Deny] after all images are signed
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  matchImageReferences:
  - glob: "ghcr.io/<org>/*"
  attestors:
  - name: cosign
    cosign:
      keyless:
        identities:
        - issuer: "https://token.actions.githubusercontent.com"
          subjectRegExp: "https://github.com/<org>/.*/.github/workflows/.*@refs/heads/main"
        ctlog:
          url: https://rekor.sigstore.dev
  validations:
  - expression: >-
      images.containers.map(image,
        verifyImageSignatures(image, [attestors.cosign])
      ).all(e, e > 0)
    message: "Image must be signed via Sigstore keyless signing from GitHub Actions (main branch)."
```

**Note:** `ImageValidatingPolicy` is cluster-scoped — there is no `namespace` field in metadata. Targeting `pods` in the core API group ensures all workloads are covered, including those created by Jobs, CronJobs, and bare pod specs. Kyverno's autogen can extend coverage to higher-level controllers but is not enabled by default for ImageValidatingPolicy.

### Deployment strategy

1. Start with `validationActions: [Audit]` — monitor violations without blocking
2. Review audit events: `kubectl get policyreport -A`
3. Move to `validationActions: [Deny]` once all images in scope are signed

### Cross-reference

For full `ImageValidatingPolicy` syntax, CEL expressions, and kyverno-cli testing: see `references/kyverno.md`.

---

## Gap Classification (for audit mode)

| Gap | Severity | Impact |
|---|---|---|
| No image signing | Critical | Any image admitted; no provenance chain |
| No CVE severity gate | Critical | Vulnerable images ship to production |
| No SBOM | High | Cannot audit what packages are running |
| Severity gate CRITICAL only | High | HIGH-severity CVEs pass undetected |
| Action versions pinned to tag | Medium | Supply chain attack via tag mutation |
| No SLSA provenance | Medium | No cryptographic link between build and artifact |
| SBOM not attested | Medium | SBOM exists but not linked to image |

---

## Recommended rollout order

1. **Sign** — establish provenance chain first
2. **Scan gate** — block CVEs from shipping
3. **SBOM** — generate and attest
4. **Enforce** — Kyverno `ImageValidatingPolicy` in Audit mode
5. **SLSA** — add Level 2 provenance attestation
6. **Enforce → Deny** — harden admission after all images are signed
