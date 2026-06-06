---
name: supply-chain
description: Secure the software supply chain from source to running container. Covers Cosign keyless image signing (Sigstore/Rekor), SBOM generation and attestation (Syft), vulnerability scanning with severity gates (Trivy/Grype), SLSA Level 2 provenance, and Kyverno/OPA admission enforcement. All open-source, no license cost. Use when asked to "sign my image", "generate an SBOM", "scan for CVEs", "attest build provenance", "enforce image signatures in Kubernetes", or "implement SLSA".
argument-hint: "[audit|sign|sbom|scan|enforce|slsa] [description or file path]"
---

Secure the software supply chain — from the build pipeline to running containers.

---

## Interactive Wizard (fires when no arguments are provided)

When invoked with no arguments, ask before proceeding:

**Q1 — Mode?**
```
What do you need?
  1. audit    — review an existing CI/CD pipeline for supply chain security gaps
  2. sign     — set up keyless image signing with Cosign (Sigstore/Rekor, no key management)
  3. sbom     — generate and attest an SBOM with Syft
  4. scan     — add a CVE vulnerability gate with Trivy or Grype
  5. enforce  — write a Kyverno policy to block unsigned images at admission
  6. slsa     — generate a SLSA Level 2 provenance workflow

Enter 1–6 or mode name:
```

**Q2 — Context** (after mode selected, one at a time):
- **audit**: `Paste your GitHub Actions workflow file(s) or describe your current CI/CD pipeline:`
- **sign**: `Which container registry? (ECR / GHCR / Docker Hub / other):`
- **sbom**: `Which image and registry? (e.g. ghcr.io/org/image):`
- **scan**: `Which scanner preference? Trivy (recommended) or Grype — or no preference:`
- **enforce**: `Which registry or image prefix should the policy cover? (e.g. ghcr.io/myorg/*):`
- **slsa**: `Which registry and repo? (e.g. ghcr.io/org/image from github.com/org/repo):`

Then proceed into the relevant mode below.

---

## Mode: audit

Review an existing CI/CD pipeline and cluster admission configuration for supply chain security gaps.

Steps:
1. Ask for or read: the GitHub Actions workflow file(s), any existing image scanning steps, and any Kyverno/OPA admission policies
2. Classify gaps by severity:
   - **Critical**: images pushed without signing, no CVE gate, unsigned images admitted to cluster
   - **High**: SBOM not generated or not attested, severity gate only on CRITICAL (misses HIGH)
   - **Medium**: action versions pinned to tag not SHA, no SLSA provenance
3. Output a prioritised gap list:
   ```
   [CRITICAL] No image signing — any image can be admitted to the cluster
   [CRITICAL] No CVE severity gate — vulnerable images pass CI
   [HIGH]     No SBOM attestation — cannot audit what is running
   [MEDIUM]   Action versions pinned to tag, not SHA
   ```
4. Recommend the fix order: sign → scan-gate → SBOM → enforce → SLSA

Reference: `references/supply-chain.md` → Gap classification, Fix order

## Mode: sign

Set up keyless image signing with Cosign using Sigstore/Rekor (no key management required).

Steps:
1. Confirm the image registry (ECR, GHCR, Docker Hub) and CI platform (GitHub Actions assumed)
2. Generate the signing workflow step:
   ```yaml
   - name: Install Cosign
     uses: sigstore/cosign-installer@11086d9f32b178aa24e93c2b86eba3ef4b16b68a  # v3.8.1

   - name: Sign image
     run: |
       cosign sign --yes \
         ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
   ```
3. Explain the keyless flow: GitHub Actions OIDC token → Fulcio CA → Rekor transparency log
4. Show verification command:
   ```bash
   cosign verify \
     --certificate-identity-regexp="https://github.com/<org>/<repo>/.github/workflows/.*" \
     --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
     ghcr.io/<org>/<image>@<digest>
   ```
5. Flag: always sign the digest (`@sha256:…`), never the tag — tags are mutable

Key rules:
- Never store signing keys in CI secrets — use keyless only
- Always sign the digest, not the tag
- Pin `cosign-installer` to a full SHA, e.g.: `sigstore/cosign-installer@11086d9f32b178aa24e93c2b86eba3ef4b16b68a`

Reference: `references/supply-chain.md` → Keyless signing, Rekor transparency log

## Mode: sbom

Generate a Software Bill of Materials with Syft and attest it as an OCI artifact alongside the image.

Steps:
1. Add the SBOM generation step after build and push (digest is only available after registry push):
   ```yaml
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
2. Show how to retrieve the SBOM attestation:
   ```bash
   cosign download attestation \
     --predicate-type https://spdx.dev/Document \
     ghcr.io/<org>/<image>@<digest> | jq '.payload | @base64d | fromjson'
   ```
3. Note: use `spdx-json` format for broadest tooling compatibility; `cyclonedx-json` is an alternative

Reference: `references/supply-chain.md` → SBOM formats, Syft, Attestation

## Mode: scan

Add a CVE vulnerability scan with a configurable severity gate that fails the build.

Steps:
1. Add Trivy scan step:
   ```yaml
   - name: Scan image for vulnerabilities
     uses: aquasecurity/trivy-action@18f2135c0b15d26b3a4c2efded75e06b6f0e4884  # v0.30.0
     with:
       image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
       format: table
       exit-code: '1'
       ignore-unfixed: true
       vuln-type: os,library
       severity: CRITICAL,HIGH
   ```
2. Explain `ignore-unfixed: true` — skip CVEs with no fix available (reduces noise without reducing security)
3. For Grype (alternative), show:
   ```yaml
   - name: Scan with Grype
     uses: anchore/scan-action@e1165082ffb1fe366ebaf02d8526e7c4989ea9d2  # v7.4.0
     with:
       image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
       fail-build: true
       severity-cutoff: high
   ```
4. Recommend Trivy for new setups (CNCF, single binary, SBOM support); Grype for teams already using Syft

Reference: `references/supply-chain.md` → Trivy vs Grype, Severity gates

## Mode: enforce

Generate a Kyverno `ImageValidatingPolicy` that blocks unsigned or unverified images at admission time.

Steps:
1. Ask: keyless (Sigstore) or key-based signing?
2. For keyless, generate:
   ```yaml
   apiVersion: policies.kyverno.io/v1
   kind: ImageValidatingPolicy
   metadata:
     name: require-signed-images
   spec:
     validationActions: [Audit]   # switch to [Deny] after all images are signing
     matchConstraints:
       resourceRules:
       - apiGroups: [""]
         apiVersions: ["v1"]
         operations: ["CREATE", "UPDATE"]
         resources: ["pods"]
     matchImageReferences:
     - glob: "ghcr.io/<org>/*"
     validations:
     - expression: >
         images.containers.map(image, verifyImageSignatures(image, [{"keyless": {
           "url": "https://fulcio.sigstore.dev",
           "rekor": {"url": "https://rekor.sigstore.dev"},
           "identities": [{"issuer": "https://token.actions.githubusercontent.com",
             "subjectRegExp": "https://github.com/<org>/.*"}]
         }}])).all(e, e > 0)
       message: "Image must be signed via Sigstore keyless signing from GitHub Actions"
   ```
3. Show audit-first deployment:
   ```yaml
   spec:
     validationActions: [Audit]   # start here, switch to [Deny] after validation
   ```
4. Cross-reference: `/platform-skills:kyverno` for full ImageValidatingPolicy guidance

Reference: `references/supply-chain.md` → Kyverno enforcement, `references/kyverno.md` → ImageValidatingPolicy

## Mode: slsa

Generate a GitHub Actions workflow for SLSA Level 2 provenance using `slsa-github-generator`.

Steps:
1. Explain what SLSA L2 gives: signed provenance linking the artifact to the specific build inputs (source commit, workflow, runner)
2. Generate the workflow using the official reusable workflow:
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
         - name: Build and push image
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
       with:
         image: ghcr.io/<org>/<image>
         digest: ${{ needs.build.outputs.digest }}
         registry-username: ${{ github.actor }}
       secrets:
         registry-password: ${{ secrets.GITHUB_TOKEN }}
   ```
3. Show provenance verification:
   ```bash
   slsa-verifier verify-image \
     ghcr.io/<org>/<image>@<digest> \
     --source-uri github.com/<org>/<repo> \
     --source-branch main
   ```
4. Note: `generator_container_slsa3.yml` produces L2 provenance by default; L3 requires hermetic builds not available on standard GitHub-hosted runners

Reference: `references/supply-chain.md` → SLSA levels, slsa-github-generator

---

After completing this task, log errors and learnings via `/platform-skills:self-improve log`.
