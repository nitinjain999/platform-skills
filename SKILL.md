---
name: platform-skills
description: Hands-on guidance for platform and DevOps engineers working with Kubernetes, Terraform, GitOps, GitHub Actions, AWS, Azure, Linkerd, Linux, and networking. Use when designing or troubleshooting Kubernetes workloads and RBAC, writing Terraform modules, configuring Flux or Argo CD, setting up CI/CD pipelines, managing cloud identity and IAM, handling secrets, diagnosing DNS or VPC connectivity, operating a service mesh, or applying product thinking to developer experience — at any scale, for any team size.
---

# Platform Skills

Use this skill for hands-on help with Kubernetes, GitOps, cloud infrastructure, CI/CD, secrets management, service mesh, Linux administration, networking, and platform product thinking — whether you are a solo developer or part of a large platform team.

## Pick the right tool for the job

Match the task to the right layer:

1. `Terraform`: Provision cloud primitives, cluster bootstrap, shared services, identity, networking, and policy foundations.
2. `Kubernetes`: Define workload, namespace, RBAC, service, policy, and platform baseline patterns that apply across distributions.
3. `OpenShift`: Adapt Kubernetes patterns to OpenShift-native routing, security, operator, and tenancy constraints.
4. `Flux` or `Argo CD`: Reconcile in-cluster desired state after bootstrap and manage promotion of workloads or platform add-ons.
5. `GitHub Actions`: Validate, package, test, and promote changes. Keep workflows declarative and reusable.
6. `AWS` or `Azure`: Apply provider-specific account, subscription, identity, and governance patterns.
7. `Linkerd`: Apply service mesh for automatic mTLS, golden-signal observability, and traffic management between workloads.
8. `Linux & Networking`: Diagnose Linux systems and network problems — DNS resolution, load balancer routing, VPC/VNet design, kernel tuning, and connectivity troubleshooting.
9. `Platform Mindset`: Treat developers as customers. Apply product thinking, friction audits, DevEx metrics, RFC/ADR processes, incident communication, and blameless post-mortems.
10. `Cross-platform`: Design repo boundaries, ownership, promotion flows, and security controls first.

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
- For Linux and networking changes, validate at each layer before escalating: confirm the process is listening (`ss -tulnp`), then L3 reachability (`ping`), L4 connectivity (`nc -zv`), L7 response (`curl -v`), and security group / NACL rules last. Do not skip layers.
- For every Terraform change, enforce in order: `terraform fmt -check -recursive`, `terraform validate`, `tflint --recursive`, security scan (`tfsec` or `checkov`), then `plan`. Do not let format or lint failures reach the plan step.
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
- For cluster baseline, workload, RBAC, and policy guidance, read [references/kubernetes.md](references/kubernetes.md).
- For OpenShift-specific operating patterns, read [references/openshift.md](references/openshift.md).
- For Flux bootstrap, reconciliation, image automation, and app delivery guidance, read [references/flux.md](references/flux.md).
- For Argo CD app delivery and application set patterns, read [references/argocd.md](references/argocd.md).
- For AWS landing zones, IAM, and EKS-oriented patterns, read [references/aws.md](references/aws.md).
- For Azure management groups, identity, and AKS-oriented patterns, read [references/azure.md](references/azure.md).
- For reusable workflows, OIDC, and delivery controls, read [references/github-actions.md](references/github-actions.md).
- For secrets strategy, External Secrets Operator, and Sealed Secrets patterns, read [references/secrets.md](references/secrets.md).
- For Linkerd service mesh, mTLS, observability, traffic management, and multi-cluster, read [references/linkerd.md](references/linkerd.md).
- For Linux administration, DNS, load balancing, VPC/VNet design, kernel tuning, and network troubleshooting, read [references/linux-networking.md](references/linux-networking.md).
- For product mindset, developer experience, friction audits, RFC/ADR, incident communication, post-mortems, and capacity planning, read [references/platform-mindset.md](references/platform-mindset.md).

Load only the files needed for the current request.

## Slash Commands

For explicit, repeatable workflows use these commands:

- `/platform-skills:debug` — structured troubleshooting for any platform symptom
- `/platform-skills:review` — production-readiness review of any manifest, Terraform, or workflow
- `/platform-skills:terraform` — full fmt/validate/tflint/security pipeline + blast radius review
- `/platform-skills:gitops` — Flux CD and Argo CD reconciliation troubleshooting
- `/platform-skills:linkerd` — Linkerd mTLS, injection, policy, and multi-cluster diagnostics
- `/platform-skills:linux` — Linux administration, DNS, load balancing, VPC/VNet, and connectivity troubleshooting
- `/platform-skills:product` — product thinking, friction audits, DevEx, RFC/ADR, incident updates, post-mortems
