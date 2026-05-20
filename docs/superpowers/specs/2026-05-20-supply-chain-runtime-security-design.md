# Design: Supply Chain Security + Runtime Security Skills

**Date:** 2026-05-20
**Status:** Approved for implementation
**Author:** Nitin Jain

---

## Summary

Add two new first-class skills to the platform-skills plugin:

1. **`/platform-skills:supply-chain`** — Secure the software supply chain from source to running container: image signing (Cosign/Sigstore), SBOM generation and attestation (Syft), vulnerability scanning (Trivy/Grype), SLSA Level 2/3 provenance, and Kyverno/OPA enforcement gates that block unsigned or unverified images at admission time.

2. **`/platform-skills:runtime-security`** — Detect and respond to threats inside running containers using Falco (eBPF-based, CNCF, open-source/free). Covers Falco installation on EKS/GKE, custom rule authoring, alert routing via Falcosidekick, and bridging runtime alerts to Kyverno enforcement.

Both skills are 100% open-source / no-license-cost tooling.

---

## Why Two Skills Instead of One

Supply chain and runtime security are operated by different teams at different points in the lifecycle:

- **Supply chain** is a CI/CD concern — build pipeline, image registry, admission control. Owned by the platform/CI team.
- **Runtime security** is a cluster operations concern — DaemonSet deployment, rule authoring, alert routing, incident response. Owned by the platform/security operations team.

Combining them into one command would make each half harder to discover and navigate.

---

## Skill 1: `/platform-skills:supply-chain`

### Activation triggers

- Files: Dockerfile, GitHub Actions workflows, `.github/workflows/*.yaml`
- Tool names: `cosign`, `syft`, `trivy`, `grype`, `slsa-verifier`
- Keywords: "sign image", "SBOM", "scan for CVEs", "attest provenance", "keyless signing", "supply chain", "Sigstore", "Rekor", "SLSA"
- Kyverno `ImageValidatingPolicy` with `verifyImages` blocks

### Modes

| Mode | What it does |
|---|---|
| `audit` | Review an existing pipeline for supply chain gaps; output a prioritised gap list |
| `sign` | Walk through Cosign keyless signing setup using Sigstore/Rekor (no key management) |
| `sbom` | Generate and attest an SBOM with Syft; attach to image as OCI attestation |
| `scan` | Trivy or Grype CVE scan with configurable severity gate (CRITICAL/HIGH exit-code policy) |
| `enforce` | Generate Kyverno `ImageValidatingPolicy` or OPA policy to block unsigned/unattested images at admission |
| `slsa` | SLSA Level 2 provenance via `slsa-github-generator` GitHub Actions reusable workflow |

### Tool stack (all open-source, no license cost)

| Tool | Purpose | CNCF? |
|---|---|---|
| Cosign (Sigstore) | Keyless image signing and verification | Yes |
| Syft | SBOM generation (SPDX, CycloneDX) | No (Anchore OSS) |
| Trivy | CVE scanning, SBOM, misconfig detection | Yes |
| Grype | CVE scanning against Syft SBOM | No (Anchore OSS) |
| Rekor | Transparency log for signatures | Yes (Sigstore) |
| slsa-github-generator | SLSA Level 2/3 provenance | Yes (OpenSSF) |
| Kyverno ImageValidatingPolicy | Admission enforcement | Yes |

### Content structure

```
references/supply-chain.md
  ├── Keyless signing with Cosign (OIDC, Rekor transparency log)
  ├── SBOM generation and attestation with Syft
  ├── Vulnerability scanning: Trivy vs Grype trade-offs
  ├── Severity gate configuration and break-the-build strategy
  ├── SLSA Level 2 vs Level 3: what each requires
  ├── Kyverno ImageValidatingPolicy: verifyImages, keyless, attestations
  ├── OPA policy: enforce signed images via Rego
  ├── Cross-references: github-actions.md, kyverno.md
  └── Troubleshooting: signature not found, SBOM attestation missing

examples/supply-chain/
  ├── sign-and-push.yaml          # GHA: build → cosign sign → push
  ├── sbom-attest.yaml            # GHA: syft SBOM → cosign attest
  ├── trivy-gate.yaml             # GHA: trivy scan with CRITICAL exit gate
  ├── kyverno-verify-image.yaml   # ImageValidatingPolicy: keyless verification
  └── slsa-provenance.yaml        # GHA: slsa-github-generator L2 provenance
```

### Key rules to enforce

- Never store signing keys in CI environment variables — use keyless (OIDC + Rekor)
- Always pin `cosign`, `syft`, `trivy` action versions to a SHA, not a tag
- Gate on CRITICAL + HIGH by default; document any exceptions in the policy
- Attest SBOM as an OCI artifact alongside the image, not as a file artefact
- Kyverno `ImageValidatingPolicy` must apply before workload admission, not as a background scan

---

## Skill 2: `/platform-skills:runtime-security`

### Activation triggers

- Files: `falco-values.yaml`, `falco-rules.yaml`, Falcosidekick config
- Keywords: "runtime security", "Falco", "syscall monitoring", "container threat detection", "privilege escalation detection", "eBPF security"
- Symptoms: "pod running unexpected binary", "shell spawned in container", "unexpected outbound connection"

### Modes

| Mode | What it does |
|---|---|
| `install` | Deploy Falco via Helm on EKS/GKE with eBPF driver (no kernel module required) |
| `rules` | Write and unit-test custom Falco rules; explain built-in ruleset |
| `alerts` | Configure Falcosidekick to route alerts → Slack, webhook, PagerDuty |
| `debug` | Diagnose why a Falco rule is not firing; explain event filter syntax |
| `harden` | Map Falco alert metadata to Kyverno enforcement or OPA policy gates |

### Tool stack (all open-source, no license cost)

| Tool | Purpose | CNCF? |
|---|---|---|
| Falco | eBPF-based syscall/kernel event monitoring | Yes |
| Falcosidekick | Alert fanout: Slack, webhook, SNS, PagerDuty | Yes (Falco ecosystem) |
| Falcosidekick UI | Alert dashboard | Yes (Falco ecosystem) |
| Helm falcosecurity/falco | Official Helm chart | Yes |

### Content structure

```
references/runtime-security.md
  ├── Falco architecture: eBPF driver vs kernel module (prefer eBPF on managed K8s)
  ├── Installing Falco on EKS with eBPF (no kernel module, Fargate caveats)
  ├── Installing Falco on GKE (COS node image, eBPF requirement)
  ├── Built-in ruleset overview: which rules to enable in production
  ├── Writing custom rules: condition syntax, output fields, priority levels
  ├── Testing rules with falco --dry-run and event-generator
  ├── Falcosidekick: routing config, output types, alert deduplication
  ├── Bridging Falco → Kyverno: using alert metadata in admission policy
  ├── Resource sizing: CPU/memory for Falco DaemonSet
  └── Troubleshooting: rule not firing, high CPU, missed events

examples/runtime-security/
  ├── falco-values.yaml              # Helm values: eBPF driver, resource limits, tolerations
  ├── falco-custom-rules.yaml        # Rules: shell in container, privilege escalation, unexpected outbound
  ├── falcosidekick-values.yaml      # Helm values: Slack + webhook routing, deduplication
  └── falco-kyverno-bridge.yaml      # Kyverno policy: deny workloads that triggered Falco critical alerts
```

### Key rules to enforce

- Always use eBPF driver on managed Kubernetes (EKS, GKE, AKS) — kernel module requires privileged access and breaks on node OS upgrades
- Never run Falco as a sidecar — it must be a DaemonSet to see all node-level syscalls
- Set `priority: WARNING` or higher for production alert routing; DEBUG/INFO are noise
- Always set resource `limits.memory` on the Falco DaemonSet — kernel event processing can spike
- Test every custom rule with `falco-event-generator` before deploying to production

---

## SKILL.md additions

Two new numbered entries in the "Pick the right tool" section:

```
25. `Supply Chain Security`: Secure the build pipeline and image lifecycle with Cosign keyless signing,
    Syft SBOM generation, Trivy/Grype scanning, SLSA Level 2 provenance, and Kyverno admission enforcement.
    All open-source, no license cost.

26. `Runtime Security`: Detect in-container threats at the syscall level with Falco (eBPF, CNCF).
    Covers rule authoring, Falcosidekick alert routing, and bridging runtime signals to admission enforcement.
```

Two new activation keyword clusters added to the skill frontmatter `description`.

Two new command entries added to `COMMANDS.md` following the same structure as `/platform-skills:keda`.

---

## Cross-references

| This skill | Links to |
|---|---|
| `supply-chain` enforce mode | `references/kyverno.md` → ImageValidatingPolicy |
| `supply-chain` scan mode | `references/github-actions.md` → CI gate patterns |
| `runtime-security` harden mode | `references/kyverno.md`, `references/opa.md` |
| `runtime-security` install mode | `references/kubernetes.md` → DaemonSet baseline |

---

## Validation steps (post-implementation)

1. `bash tests/validate-skill.sh` — passes all existing checks
2. New supply-chain examples pass `yamllint` and `kubeconform`
3. New runtime-security Helm values pass `helm lint falcosecurity/falco -f examples/runtime-security/falco-values.yaml`
4. COMMANDS.md entry count increases by 2
5. SKILL.md numbered list increases from 24 to 26

---

## Rollback plan

Both skills are purely additive — new files in `references/`, `examples/`, and appended entries in `SKILL.md` and `COMMANDS.md`. Rollback = revert the branch. No existing files are modified beyond appending.

---

## Out of scope

- Paid tools (Aqua, Snyk, Twistlock, Sysdig) — excluded by license constraint
- Falco on AWS Fargate — Fargate does not expose the node kernel; noted as a caveat in the reference, not a supported path
- SLSA Level 3 (hermetic builds) — covered in the reference as future state; the example targets Level 2 which is achievable with GitHub Actions today
