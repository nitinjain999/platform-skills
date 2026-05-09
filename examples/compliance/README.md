Status: Stable

# Compliance Examples

SOC 2 Trust Services Criteria controls implemented as Terraform — covering IAM, encryption, audit logging, network security, detection, incident response, vulnerability management, and backup.

## Examples

| Example | TSC Criterion | Description |
|---------|--------------|-------------|
| [iam/irsa-role.tf](iam/irsa-role.tf) | CC6.1, CC6.2 | IRSA application role and GitHub Actions OIDC trust |
| [iam/scp-mfa.tf](iam/scp-mfa.tf) | CC6.2 | SCP enforcing MFA and blocking privilege escalation |
| [logging/cloudtrail.tf](logging/cloudtrail.tf) | CC7.2 | Multi-region CloudTrail with KMS encryption and object lock |
| [logging/aws-config.tf](logging/aws-config.tf) | CC7.2 | AWS Config recorder with 12 SOC 2 managed rules |
| [logging/vpc-flow-logs.tf](logging/vpc-flow-logs.tf) | CC6.6, CC7.2 | VPC flow logs to S3 |
| [network/waf.tf](network/waf.tf) | CC6.6 | WAF with rate limiting and AWS managed rule groups |
| [network/security-groups.tf](network/security-groups.tf) | CC6.6 | Least-privilege security group baseline |
| [encryption-data-services/](encryption-data-services/) | CC6.7 | KMS encryption for DynamoDB, ECR, ElastiCache, OpenSearch, Kinesis, EFS, Redshift |
| [detection/guardduty.tf](detection/guardduty.tf) | CC7.1 | GuardDuty with S3, EKS, and malware protection sources |
| [detection/cloudwatch-alarms.tf](detection/cloudwatch-alarms.tf) | CC7.1 | 14 CIS Benchmark CloudWatch metric filters and alarms |
| [detection/security-hub.tf](detection/security-hub.tf) | CC7.1 | Security Hub with AWS Foundational and CIS standards |
| [incident-response/sns.tf](incident-response/sns.tf) | CC7.3 | KMS-encrypted SNS for GuardDuty HIGH/CRITICAL events |
| [vulnerability/inspector.tf](vulnerability/inspector.tf) | CC6.8 | Inspector v2 with ECR enhanced scanning |
| [backup/backup-plan.tf](backup/backup-plan.tf) | A1.2, A1.3 | AWS Backup plan, vault lock, and cross-region DR |
| [checkov-config.yaml](checkov-config.yaml) | All | Checkov config grouping SOC 2 check IDs by criterion |

## Quick Start

```bash
# Install Checkov
pip install checkov

# Run all SOC 2 checks against your Terraform
checkov -d . --config-file examples/compliance/checkov-config.yaml

# Run checks for a specific criterion (e.g. CC6.7 encryption)
checkov -d . --check CKV_AWS_7,CKV_AWS_19,CKV_AWS_16,CKV_AWS_17

# Validate a single file
checkov -f logging/cloudtrail.tf
```

## Apply an example

```bash
cd examples/compliance/logging
terraform init
terraform plan -var="environment=production"
```

## SOC 2 Coverage Map

| Criterion | Control | Example File |
|-----------|---------|-------------|
| CC6.1 | IAM least privilege, IRSA | `iam/irsa-role.tf` |
| CC6.2 | MFA enforcement, OIDC | `iam/scp-mfa.tf` |
| CC6.6 | Network security, WAF, flow logs | `network/`, `logging/vpc-flow-logs.tf` |
| CC6.7 | Encryption at rest (11 services) | `encryption-data-services/` |
| CC6.8 | Vulnerability scanning | `vulnerability/inspector.tf` |
| CC7.1 | Detection: GuardDuty, CIS alarms, Security Hub | `detection/` |
| CC7.2 | Audit logging: CloudTrail, Config, VPC flow logs | `logging/` |
| CC7.3 | Incident response: SNS, EventBridge | `incident-response/` |
| CC8.1 | Change management: S3 backend, locking | referenced in `references/compliance.md` |
| A1.1 | Availability: multi-AZ | referenced in `references/compliance.md` |
| A1.2/A1.3 | Backup and recovery | `backup/backup-plan.tf` |

## Checkov Suppressions

Use the documented suppression format in `checkov-config.yaml` to acknowledge accepted risks:

```hcl
#checkov:skip=CKV_AWS_18:Access logging not required for this internal bucket
resource "aws_s3_bucket" "internal_logs" { ... }
```

## See Also

- [references/compliance.md](../../references/compliance.md) — full SOC 2 TSC mapping, Terraform patterns, Checkov rules, evidence commands, pre-audit checklist
- `/platform-skills:compliance` — gap analysis, control implementation, evidence collection, Checkov remediation, full readiness checklist
