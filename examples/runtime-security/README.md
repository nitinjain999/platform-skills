# Runtime Security Examples

Status: Stable

Working examples for the `/platform-skills:runtime-security` skill.

## Files

| File | Description |
|---|---|
| `falco-values.yaml` | Helm values: Falco with eBPF driver, resource limits, node tolerations |
| `falco-custom-rules.yaml` | Custom rules: shell in container, privilege escalation, unexpected outbound |
| `falcosidekick-values.yaml` | Helm values: Falcosidekick with Slack and webhook routing |
| `falco-kyverno-bridge.yaml` | Kyverno ValidatingPolicy: block re-admission of Falco-flagged workloads |

## Usage

```bash
# Install Falco
helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  -f examples/runtime-security/falco-values.yaml

# Install with Falcosidekick
helm upgrade --install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set falcosidekick.enabled=true \
  -f examples/runtime-security/falcosidekick-values.yaml

# Apply Kyverno bridge policy
kubectl apply -f examples/runtime-security/falco-kyverno-bridge.yaml
```

## Validation

```bash
bash examples/runtime-security/runtime-security-validate.sh
```
