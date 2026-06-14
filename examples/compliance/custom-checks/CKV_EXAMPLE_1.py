"""
CKV_EXAMPLE_1 — Enforce required tags on common AWS resources.

Check ID convention: CKV_<ORG_ABBREVIATION>_<NUMBER>
Copy this file, rename it, update the id, name, supported_resources, and scan logic.

Run with:
  checkov -d . --external-checks-dir custom-checks
"""
from checkov.common.models.enums import CheckResult, CheckCategories
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck
from typing import Any


class EnforceRequiredTags(BaseResourceCheck):
    def __init__(self) -> None:
        name = "Ensure resource has required tags: team and environment"
        id = "CKV_EXAMPLE_1"
        supported_resources = ("aws_instance", "aws_s3_bucket", "aws_db_instance")
        categories = (CheckCategories.GENERAL_SECURITY,)
        super().__init__(
            name=name,
            id=id,
            categories=categories,
            supported_resources=supported_resources,
        )

    def scan_resource_conf(self, conf: dict[str, list[Any]]) -> CheckResult:
        tags = conf.get("tags", [{}])
        tag_map = tags[0] if isinstance(tags, list) and tags else tags
        if isinstance(tag_map, dict) and "team" in tag_map and "environment" in tag_map:
            return CheckResult.PASSED
        self.details.append("Missing required tags: 'team' and/or 'environment'")
        return CheckResult.FAILED


check = EnforceRequiredTags()
