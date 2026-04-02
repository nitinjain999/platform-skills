# AWS Examples

Status: committed file-level snippets for the handbook. Use these as building blocks rather than a complete standalone AWS stack.

## Files

| File | What it shows |
|---|---|
| [iam/s3-least-privilege.json](iam/s3-least-privilege.json) | S3 IAM policy scoped to specific bucket and prefix |
| [iam/irsa-dynamodb.json](iam/irsa-dynamodb.json) | DynamoDB IAM policy for IRSA with leading key condition |

For EKS infrastructure, see [examples/terraform/eks-cluster/](../terraform/eks-cluster/).

## Patterns

### EKS with IRSA

```hcl
module "irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "my-app-irsa"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["my-app:my-app-sa"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.my_app.arn
  }
}
```

### ALB Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/id
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  ingressClassName: alb
  rules:
  - host: my-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

## Troubleshooting

### EKS node not joining
1. Check IAM role trust relationship
2. Verify security group allows cluster communication
3. Check cloud-init: `sudo cat /var/log/cloud-init-output.log`
4. Verify correct AMI for the Kubernetes version

### IRSA not working
1. Verify OIDC provider exists and matches the cluster endpoint
2. Check service account annotation on the pod
3. Verify the IAM role trust policy includes the correct OIDC condition

### ALB ingress not creating
1. Check AWS Load Balancer Controller logs
2. Verify IAM policy covers required actions
3. Verify subnet tags: `kubernetes.io/role/elb=1`
