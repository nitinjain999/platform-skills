# KEDA Examples

Working examples for KEDA (Kubernetes Event-Driven Autoscaling) ScaledObject and ScaledJob configurations.

## Files

| File | Trigger | Use case |
|---|---|---|
| [scaledobject-sqs.yaml](scaledobject-sqs.yaml) | AWS SQS + IRSA | Scale a Deployment based on SQS queue depth |
| [scaledobject-prometheus.yaml](scaledobject-prometheus.yaml) | Prometheus + Cron | Scale on HTTP request rate with business-hours floor |
| [scaledobject-kafka.yaml](scaledobject-kafka.yaml) | Kafka SASL/TLS | Scale on consumer group lag |
| [scaledjob-sqs.yaml](scaledjob-sqs.yaml) | AWS SQS + IRSA | Create one Job per SQS message (batch processing) |

## Quick start

```bash
# Install KEDA
helm repo add kedacore https://kedacore.github.io/charts
helm upgrade --install keda kedacore/keda \
  --namespace keda --create-namespace --version 2.14.0

# Apply a ScaledObject
kubectl apply -f scaledobject-sqs.yaml

# Check status
kubectl get scaledobject -n orders
kubectl describe scaledobject orders-processor -n orders
```

## Auth patterns

All examples use either IRSA (AWS) or a TriggerAuthentication referencing a Kubernetes Secret. Never commit static credentials to Git — use External Secrets Operator to render the Secret at runtime.

See [references/keda.md](../../references/keda.md) for the full reference guide.
