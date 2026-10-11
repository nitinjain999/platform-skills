package terraform.tags_test

import rego.v1

import data.terraform.tags

_plan(after) := {"resource_changes": [{
	"address": "aws_s3_bucket.logs",
	"type": "aws_s3_bucket",
	"change": {"actions": ["create"], "after": after},
}]}

test_deny_missing_cost_center if {
	msgs := tags.deny with input as _plan({"tags_all": {"owner": "platform-team", "environment": "production"}})
	msgs == {`aws_s3_bucket.logs is missing required tags: ["cost-center"]`}
}

test_deny_empty_value if {
	count(tags.deny) == 1 with input as _plan({"tags_all": {"owner": " ", "cost-center": "cc-4021", "environment": "production"}})
}

test_allow_all_tags_from_default_tags if {
	count(tags.deny) == 0 with input as _plan({"tags_all": {"owner": "platform-team", "cost-center": "cc-4021", "environment": "production"}})
}

test_allow_untaggable_resource if {
	count(tags.deny) == 0 with input as _plan({"policy": "{}"})
}

test_skip_delete if {
	plan := {"resource_changes": [{"address": "aws_s3_bucket.old", "type": "aws_s3_bucket", "change": {"actions": ["delete"], "after": null}}]}
	count(tags.deny) == 0 with input as plan
}

test_override_required_keys if {
	msgs := tags.deny with input as _plan({"tags_all": {"owner": "platform-team"}})
		with data.finops.required_tags as ["owner"]
	count(msgs) == 0
}
