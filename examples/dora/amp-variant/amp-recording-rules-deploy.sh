#!/usr/bin/env bash
# Deploy DORA Prometheus recording rules to Amazon Managed Prometheus.
# AMP does not read rule files from disk — rules must be created via AWS CLI.
#
# Usage:
#   bash examples/dora/amp-variant/amp-recording-rules-deploy.sh <workspace-id> [region]
#
# Prerequisites:
#   - AWS CLI v2 with aps:CreateRuleGroupsNamespace and aps:PutRuleGroupsNamespace
#   - examples/dora/prometheus-recording-rules.yaml present (uses the same rule content)
#
# Run from repository root: bash examples/dora/amp-variant/amp-recording-rules-deploy.sh <id>

set -euo pipefail

WORKSPACE_ID="${1:?Usage: $0 <workspace-id> [region]}"
REGION="${2:-eu-central-1}"
NAMESPACE="dora-rules"
RULES_FILE="examples/dora/prometheus-recording-rules.yaml"

if [[ ! -f "$RULES_FILE" ]]; then
  echo "ERROR: $RULES_FILE not found. Run from the repository root." >&2
  exit 1
fi

# Check if the namespace already exists.
EXISTING=$(aws amp list-rule-groups-namespaces \
  --workspace-id "$WORKSPACE_ID" \
  --region "$REGION" \
  --query "ruleGroupsNamespaces[?name=='${NAMESPACE}'].name" \
  --output text 2>/dev/null || echo "")

if [[ -z "$EXISTING" ]]; then
  echo "Creating AMP rule groups namespace '${NAMESPACE}' in workspace ${WORKSPACE_ID}..."
  aws amp create-rule-groups-namespace \
    --workspace-id "$WORKSPACE_ID" \
    --name "$NAMESPACE" \
    --data "fileb://${RULES_FILE}" \
    --region "$REGION"
  echo "PASS: created namespace '${NAMESPACE}'"
else
  echo "Updating AMP rule groups namespace '${NAMESPACE}' in workspace ${WORKSPACE_ID}..."
  aws amp put-rule-groups-namespace \
    --workspace-id "$WORKSPACE_ID" \
    --name "$NAMESPACE" \
    --data "fileb://${RULES_FILE}" \
    --region "$REGION"
  echo "PASS: updated namespace '${NAMESPACE}'"
fi

# Verify the namespace status is ACTIVE.
STATUS=$(aws amp describe-rule-groups-namespace \
  --workspace-id "$WORKSPACE_ID" \
  --name "$NAMESPACE" \
  --region "$REGION" \
  --query "ruleGroupsNamespace.status.statusCode" \
  --output text)

if [[ "$STATUS" == "ACTIVE" ]]; then
  echo "PASS: namespace '${NAMESPACE}' is ACTIVE"
else
  echo "WARN: namespace '${NAMESPACE}' status is '${STATUS}' — may still be propagating"
fi

echo ""
echo "Verify rules are loaded in AMP:"
echo "  aws amp describe-rule-groups-namespace \\"
echo "    --workspace-id ${WORKSPACE_ID} \\"
echo "    --name ${NAMESPACE} \\"
echo "    --region ${REGION}"
