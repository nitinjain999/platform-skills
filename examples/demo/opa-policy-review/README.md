# Demo: OPA Policy Review

> Status: Stable

An OPA/Rego admission policy with a critical default-allow flaw. Platform-skills catches it and generates a production-safe replacement.

## What's wrong with bad.rego

| Finding | Severity | Risk |
|---|---|---|
| `default allow = true` — allow-by-default | Critical | Any pod not explicitly denied passes — policy is opt-out, not opt-in |
| Uses `allow = false` reassignment | High | Rego v0 style; undefined behaviour when multiple rules conflict |
| Only checks privileged containers | High | Root containers, missing limits, hostNetwork all bypass the policy |
| No `deny` set — single boolean | Medium | Cannot return meaningful error messages to the user |
| No `import rego.v1` | Medium | Deprecated syntax; will break in OPA ≥1.0 |

## What changed in fixed.rego

- `default allow := false` — deny-by-default; nothing passes unless explicitly permitted
- `deny contains msg` set — each violation returns a human-readable message
- Covers 4 controls: privileged, runAsNonRoot, resource limits, hostNetwork
- `import rego.v1` — explicit Rego v1 syntax, forward-compatible
- `any_violation` helper — single allow rule, no conflicting reassignments

## Blast radius of bad.rego

- A pod with `runAsNonRoot: false` and no memory limit deploys to production unblocked
- `hostNetwork: true` workload gets access to node network — lateral movement risk
- Policy gives a false sense of security — teams think they're protected, they're not

## Validation

```bash
# Install conftest
brew install conftest

# Test the fixed policy against a violating pod spec
conftest test --policy fixed.rego --namespace kubernetes.admission ./test-pod.yaml

# Lint with Regal
brew install styrainc/packages/regal
regal lint fixed.rego
```

## Try it yourself

```text
Use $platform-skills to review this OPA/Rego admission policy for correctness.
Check: default deny, rule conflicts, coverage gaps, Rego v1 syntax, and unit test coverage.
```
