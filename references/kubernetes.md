# Kubernetes Reference

## Contents

- Scope
- Platform baseline
- Workload patterns
- Security and policy
- Operational rules

## Scope

Use plain Kubernetes guidance for:

- Cluster baseline standards that apply across distributions
- Namespace, RBAC, network policy, and workload conventions
- Deployment, service, ingress, config, and secret operating practices
- Platform add-on dependencies that are not specific to one GitOps tool

Use Kubernetes as the common application runtime contract. Layer distribution-specific details in OpenShift guidance and reconciliation-specific details in Flux or Argo CD guidance.

## Platform baseline

Define a minimum platform baseline for every cluster:

- Namespaces with clear ownership boundaries
- Resource requests and limits on workloads
- Liveness, readiness, and startup probes
- Pod disruption budgets for critical services
- Network policies on app namespaces
- Standard labels and annotations for ownership, environment, and compliance

Prefer admission, policy, or template enforcement over relying on human review.

## Workload patterns

Prefer these defaults:

- `Deployment` for stateless applications
- `StatefulSet` only when identity or stable storage matters
- `Ingress` or `Gateway` patterns for north-south traffic
- `ConfigMap` for non-sensitive configuration and external secret stores for secrets
- Horizontal Pod Autoscaler only when requests and metrics are defined clearly

Keep manifests small, composable, and environment-agnostic where possible.

## Security and policy

- Run workloads as non-root unless there is a justified exception.
- Drop unnecessary Linux capabilities.
- Prefer read-only root filesystems where practical.
- Use service accounts intentionally; do not let everything run as `default`.
- Enforce image provenance, namespace controls, and policy checks before deployment.

## Operational rules

- Treat Git as the source of truth for declared state.
- Avoid imperative hotfixes in-cluster without a corresponding Git change.
- Standardize debugging commands, event inspection, and health checks for every workload type.
- Keep rollout and rollback procedures visible in deployment documentation.
