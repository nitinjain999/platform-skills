# Supply Chain Security Examples

Status: Stable

Working examples for the `/platform-skills:supply-chain` skill.

## Files

| File | Description |
|---|---|
| `sign-and-push.yaml` | GitHub Actions: build, sign with Cosign keyless, and push |
| `sbom-attest.yaml` | GitHub Actions: generate SBOM with Syft and attest |
| `trivy-gate.yaml` | GitHub Actions: Trivy CVE scan with CRITICAL+HIGH severity gate |
| `kyverno-verify-image.yaml` | Kyverno ImageValidatingPolicy: block unsigned images |
| `slsa-provenance.yaml` | GitHub Actions: SLSA Level 2 provenance via slsa-github-generator |

## Usage

Copy the relevant file into your `.github/workflows/` or `policies/` directory and substitute `<org>` and `<image>` placeholders.

## Validation

```bash
bash examples/supply-chain/supply-chain-validate.sh
```
