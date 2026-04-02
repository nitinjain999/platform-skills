# GitHub Actions Examples

This directory contains reference implementations for GitHub Actions CI/CD patterns with security best practices.

Status: top-level workflows are runnable examples. Reusable workflows and composite actions are partial building blocks for handbook use.

## Examples

### 1. Terraform CI/CD

[terraform-cicd.yml](terraform-cicd.yml) - Complete Terraform validation and deployment pipeline

**Use case:** Automated Terraform plan on PR, apply on merge  
**Pattern:** OIDC authentication, protected environments, required approvals  
**Components:**
- PR validation (fmt, validate, tflint, checkov)
- Terraform plan with reviewable output
- Protected production apply with approval

### 2. Container Build and Push

[container-build.yml](container-build.yml) - Secure container image build and registry push

**Use case:** Build and push images to ECR/ACR  
**Pattern:** Multi-stage builds, vulnerability scanning, tag strategies  
**Components:**
- Docker build with caching
- Trivy vulnerability scanning
- OIDC authentication to cloud registries
- Immutable tag generation

### 3. Flux GitOps Sync

[flux-sync.yml](flux-sync.yml) - Validate and update Flux manifests

**Use case:** Validate Flux resources before merge  
**Pattern:** flux check, kustomize build, manifest validation  
**Components:**
- Flux resource validation
- Kustomize build check
- Kubernetes manifest policy validation

### 4. Reusable Workflows

[reusable-workflows/](reusable-workflows/) - Shared workflow templates

**Use case:** DRY principle for common patterns  
**Pattern:** Callable workflows with inputs  
**Components:**
- AWS OIDC authentication workflow
- Terraform plan/apply workflow
- Security scanning workflow

### 5. Composite Actions

[composite-actions/](composite-actions/) - Reusable action definitions

**Use case:** Package common step sequences  
**Pattern:** Composite actions with inputs/outputs  
**Components:**
- Setup Terraform with caching
- Configure AWS credentials
- Post PR comments

## Prerequisites

- GitHub repository with Actions enabled
- AWS/Azure account (for cloud examples)
- OIDC identity provider configured in cloud account
- Protected environments configured for production

## Security Best Practices

### 1. Pin Action Versions to SHA

```yaml
# ❌ Vulnerable to tag hijacking
- uses: actions/checkout@v4

# ✅ Pinned to immutable SHA
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

### 2. Limit Token Permissions

```yaml
# ✅ Explicit minimal permissions
permissions:
  contents: read
  pull-requests: write
  id-token: write  # For OIDC
```

### 3. Use OIDC, Not Static Credentials

```yaml
# ❌ Long-lived access keys
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@e3dd6fc3031e9e84c1c92d0232e2a259f6a2eb8a  # v4.0.2
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

# ✅ OIDC with short-lived tokens
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@e3dd6fc3031e9e84c1c92d0232e2a259f6a2eb8a  # v4.0.2
  with:
    role-to-assume: arn:aws:iam::123456789012:role/github-actions-role
    aws-region: us-east-1
```

### 4. Never Use pull_request_target for Untrusted Code

```yaml
# ❌ DANGEROUS - runs untrusted code with write access
on:
  pull_request_target:
    types: [opened, synchronize]

# ✅ Safe - runs in isolated context
on:
  pull_request:
    types: [opened, synchronize]
```

### 5. Use Environment Protection Rules

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production  # Requires approval
    steps:
      - name: Deploy to production
        run: terraform apply -auto-approve
```

## Common Patterns

### Terraform Plan on PR

```yaml
name: Terraform Plan

on:
  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-plan.yml'

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - uses: hashicorp/setup-terraform@a1502cd9e758c50496cc9ac5013915b74a51c08a  # v3.0.0
        with:
          terraform_version: 1.7.0

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@e3dd6fc3031e9e84c1c92d0232e2a259f6a2eb8a  # v4.0.2
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Terraform Init
        run: terraform init
        working-directory: terraform

      - name: Terraform Validate
        run: terraform validate
        working-directory: terraform

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color -out=tfplan
        working-directory: terraform
        continue-on-error: true

      - name: Comment PR
        uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea  # v7.0.1
        with:
          script: |
            const output = `#### Terraform Plan 📖
            \`\`\`
            ${{ steps.plan.outputs.stdout }}
            \`\`\`
            `;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })
```

### Matrix Strategy for Multi-Environment

```yaml
strategy:
  matrix:
    environment:
      - dev
      - staging
      - production
    include:
      - environment: dev
        aws_region: us-east-1
        aws_role: arn:aws:iam::111111111111:role/dev-role
      - environment: staging
        aws_region: us-east-1
        aws_role: arn:aws:iam::222222222222:role/staging-role
      - environment: production
        aws_region: us-west-2
        aws_role: arn:aws:iam::333333333333:role/prod-role

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ matrix.environment }}
    steps:
      - name: Deploy to ${{ matrix.environment }}
        run: |
          echo "Deploying to ${{ matrix.environment }}"
          echo "Region: ${{ matrix.aws_region }}"
```

### Caching Dependencies

```yaml
- name: Cache Terraform
  uses: actions/cache@13aacd865c20de90d75de3b17ebe84f7a17d57d2  # v4.0.0
  with:
    path: |
      ~/.terraform.d/plugin-cache
      .terraform
    key: ${{ runner.os }}-terraform-${{ hashFiles('**/.terraform.lock.hcl') }}
    restore-keys: |
      ${{ runner.os }}-terraform-
```

### Conditional Execution

```yaml
# Only run on main branch
if: github.ref == 'refs/heads/main'

# Only run for specific file changes
if: contains(github.event.head_commit.modified, 'terraform/')

# Only run for specific labels
if: contains(github.event.pull_request.labels.*.name, 'deploy')
```

## OIDC Setup

### AWS IAM Role for GitHub Actions

```hcl
# Create OIDC provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Create role assumable by GitHub Actions
resource "aws_iam_role" "github_actions" {
  name = "github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }]
  })
}

# Attach policies
resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"  # Adjust as needed
}
```

### Azure Service Principal for GitHub Actions

```bash
# Create OIDC application
az ad app create --display-name github-actions

# Create service principal
az ad sp create --id <app-id>

# Create federated credentials
az ad app federated-credential create \
  --id <app-id> \
  --parameters '{
    "name": "github-actions-federated",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Assign role
az role assignment create \
  --assignee <app-id> \
  --role Contributor \
  --scope /subscriptions/<subscription-id>
```

## Workflow Organization

```
.github/
├── workflows/
│   ├── terraform-pr.yml          # PR validation
│   ├── terraform-apply.yml       # Production apply
│   ├── container-build.yml       # Image builds
│   ├── flux-validate.yml         # Flux checks
│   └── _reusable-*.yml          # Reusable workflows (prefix with _)
├── actions/
│   ├── setup-terraform/          # Composite actions
│   ├── configure-cloud/
│   └── post-pr-comment/
└── CODEOWNERS                    # Review requirements
```

## Troubleshooting

### Workflow Not Running

- Check branch protection rules
- Verify trigger conditions (paths, branches)
- Check permissions in repository settings

### OIDC Authentication Failing

```bash
# Check OIDC provider exists
aws iam list-open-id-connect-providers

# Verify role trust policy
aws iam get-role --role-name github-actions-role --query 'Role.AssumeRolePolicyDocument'

# Check subject claim format
# Should be: repo:ORG/REPO:ref:refs/heads/BRANCH
```

### Permissions Denied

- Check `permissions:` block in workflow
- Verify GITHUB_TOKEN scope in repository settings
- Check branch protection rules

### Secrets Not Available

- Environment secrets only available to jobs with `environment:`
- Organization secrets must be enabled for repository
- Secret names are case-sensitive

## Performance Optimization

### Parallel Jobs

```yaml
jobs:
  validate:
    runs-on: ubuntu-latest
    # ... validation steps

  security-scan:
    runs-on: ubuntu-latest
    # ... security scanning

  deploy:
    runs-on: ubuntu-latest
    needs: [validate, security-scan]  # Wait for both
    # ... deployment
```

### Job Concurrency

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true  # Cancel old runs
```

### Self-Hosted Runners

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, linux, x64]
    # Faster for large downloads, persistent caching
```

## Further Reading

- [GitHub Actions Security Guide](https://docs.github.com/en/actions/security-guides)
- [OIDC with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
