# Kyverno Examples

Working Kyverno policy examples. Each subdirectory is independently testable with `kyverno test .`.

## Structure

```
policies/         # ClusterPolicy manifests
resources/        # Sample Kubernetes resources used in tests
kyverno-test.yaml # kyverno-cli test manifest
```

## Prerequisites

```bash
brew install kyverno      # macOS
# or see references/kyverno.md for binary install
```

## Run tests

```bash
kyverno test .
```

## Apply to real manifests (no cluster required)

```bash
kyverno apply ./policies/ --resource ./resources/ --detailed-results
```
