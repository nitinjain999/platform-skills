---
name: platform-skills
description: Platform engineering guidance for GitOps, cloud foundations, and delivery automation across Kubernetes, OpenShift, Flux, Argo CD, Terraform, AWS, Azure, and GitHub Actions. Use when Claude needs to design or review platform architectures, landing zones, Kubernetes delivery workflows, OpenShift operating patterns, Argo CD or Flux GitOps layouts, infrastructure module designs, CI/CD pipelines, identity patterns, environment promotion models, or cross-tool operating practices for a shared platform team.
---

# Platform Skills

Use this skill to turn broad platform requests into a coherent operating model instead of answering each tool in isolation.

## Start with the Control Plane

Classify the request before proposing implementation:

1. `Terraform`: Provision cloud primitives, cluster bootstrap, shared services, identity, networking, and policy foundations.
2. `Kubernetes`: Define workload, namespace, RBAC, service, policy, and platform baseline patterns that apply across distributions.
3. `OpenShift`: Adapt Kubernetes patterns to OpenShift-native routing, security, operator, and tenancy constraints.
4. `Flux` or `Argo CD`: Reconcile in-cluster desired state after bootstrap and manage promotion of workloads or platform add-ons.
5. `GitHub Actions`: Validate, package, test, and promote changes. Keep workflows declarative and reusable.
6. `AWS` or `Azure`: Apply provider-specific account, subscription, identity, and governance patterns.
7. `Cross-platform`: Design repo boundaries, ownership, promotion flows, and security controls first.

If a task spans multiple areas, decide which layer owns the source of truth and keep the other layers consumers of that state.

## Apply These Platform Rules

- Separate reusable platform building blocks from live environment configuration.
- Prefer GitOps pull-based reconciliation for cluster state and CI push-based automation for validation and packaging.
- Choose either Flux or Argo CD for a given ownership boundary unless the task is explicitly about migration between them.
- Keep Terraform responsible for bootstrapping clusters, cloud resources, secrets backends, and access primitives. Do not let Flux or Argo CD recreate those foundations unless there is a deliberate controller-based design.
- Use Flux or Argo CD for in-cluster add-ons, workloads, Helm releases, and app-level environment promotion after bootstrap.
- Use GitHub Actions for checks, plans, policy gates, artifact publishing, and promotion orchestration. Do not store long-lived environment truth in workflow YAML.
- Prefer OIDC or workload identity over static cloud credentials.
- Model environments explicitly. Promotion should be visible in Git history and reversible by commit rollback.
- Standardize policy, naming, tagging, and observability across AWS and Azure instead of allowing each repository to invent its own conventions.
- Enforce a tag baseline on all cloud resources. The specific keys are an organizational decision. Use AWS `default_tags` (provider level) or Azure `merge(local.common_tags, {...})` (module local) so the baseline is applied once, not repeated per resource. Back it with AWS Tag Policies or Azure Policy so resources created outside Terraform are also covered.

## Structure the Response

For design or implementation work, provide output in this order:

1. Target architecture and ownership boundaries
2. Repository or directory layout
3. Identity, secrets, and promotion model
4. Validation and deployment workflow
5. Risks, tradeoffs, and migration path

When asked to generate code, start from the thinnest useful slice that proves the pattern and note which layer remains intentionally out of scope.

## Pick the Right Reference Files

- For repo topology, boundaries, and promotion flow, read [references/platform-operating-model.md](references/platform-operating-model.md).
- For Terraform module, environment, testing, and state guidance, read [references/terraform.md](references/terraform.md).
- For cluster baseline, workload, and policy guidance, read [references/kubernetes.md](references/kubernetes.md).
- For OpenShift-specific operating patterns, read [references/openshift.md](references/openshift.md).
- For Flux bootstrap, reconciliation, and app delivery guidance, read [references/flux.md](references/flux.md).
- For Argo CD app delivery and application set patterns, read [references/argocd.md](references/argocd.md).
- For AWS landing zones, IAM, and EKS-oriented patterns, read [references/aws.md](references/aws.md).
- For Azure management groups, identity, and AKS-oriented patterns, read [references/azure.md](references/azure.md).
- For reusable workflows, OIDC, and delivery controls, read [references/github-actions.md](references/github-actions.md).

Load only the files needed for the current request.
