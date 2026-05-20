# Chaos Engineering Examples
Status: Stable

Working examples for the `/platform-skills:chaos` skill.

## Files

| File | Description |
|---|---|
| `litmus-install-values.yaml` | Helm values: Litmus Chaos v3 with resource limits |
| `chaos-mesh-install-values.yaml` | Helm values: Chaos Mesh v2 with resource limits |
| `pod-delete-experiment.yaml` | Litmus ChaosEngine: pod-delete with HTTP steady-state probe |
| `network-loss-experiment.yaml` | Chaos Mesh NetworkChaos: 20% packet loss for 60s |
| `cpu-stress-experiment.yaml` | Litmus pod-cpu-hog with Prometheus steady-state probe |
| `chaos-schedule.yaml` | Weekly pod-delete ChaosSchedule (staging only) |
| `gameday-runbook.md` | Structured GameDay template |

## Usage

```bash
# Install Litmus Chaos
helm upgrade --install chaos litmuschaos/litmus \
  --namespace litmus --create-namespace --version 3.9.0 \
  -f examples/chaos/litmus-install-values.yaml

# Apply a pod-delete experiment
kubectl apply -f examples/chaos/pod-delete-experiment.yaml

# Check result
kubectl get chaosresult -n my-namespace
```

## Validation

```bash
bash examples/chaos/chaos-validate.sh
```
