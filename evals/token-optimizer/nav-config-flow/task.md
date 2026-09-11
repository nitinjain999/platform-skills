# Task: Trace a service's configuration flow

You have three layers:
- `eks-cluster/` — Terraform that provisions the EKS cluster
- `infrastructure/` — Flux Kustomizations deploying platform services
- `apps/` — Application deployments

Trace the configuration flow from infrastructure to application:

1. What VPC and subnet configuration does the Terraform create?
2. Which Flux Kustomization deploys the ingress controller?
3. What namespace do applications land in?
4. How does the application ingress connect to the platform ingress controller?

State what was omitted or truncated. Report complete, partial, or blocked.
