# OpenShift Reference

## Contents

- Scope
- Platform-specific constraints
- GitOps and app delivery
- Security and tenancy
- Day-2 operations

## Scope

Use OpenShift guidance when the request involves:

- OpenShift-specific security context constraints
- Routes, operators, machine configs, or cluster version management
- Multi-tenant namespace/project patterns on Red Hat OpenShift
- Integrating platform add-ons with OpenShift defaults and guardrails

Start from standard Kubernetes patterns, then adapt to OpenShift-native controls rather than fighting them.

## Platform-specific constraints

- OpenShift commonly enforces restricted security defaults that will break manifests written for permissive vanilla Kubernetes clusters.
- Validate UID, FSGroup, capability, and privilege assumptions early.
- Prefer Operators for platform capabilities that OpenShift already manages well.
- Use `Route` when exposing workloads through OpenShift ingress patterns instead of forcing generic ingress designs everywhere.

## GitOps and app delivery

- Separate cluster configuration, platform operators, and application workloads.
- Use Argo CD or OpenShift GitOps for declarative reconciliation where that is the chosen platform standard.
- Keep cluster-admin operations isolated from app team delivery paths.
- Test Helm charts and raw manifests against OpenShift SCC and admission requirements before promotion.

## Security and tenancy

- Prefer OpenShift projects with clear ownership and quota boundaries.
- Define role bindings narrowly; avoid broad cluster-wide permissions for app teams.
- Use image streams or approved registries where governance requires them.
- Document exceptions when workloads need elevated SCCs or privileged access.

## Day-2 operations

- Track operator upgrade impact on workloads and cluster add-ons.
- Plan for cluster version upgrades explicitly; do not assume app manifests remain valid across upgrades.
- Include route, certificate, and registry diagnostics in standard OpenShift runbooks.
