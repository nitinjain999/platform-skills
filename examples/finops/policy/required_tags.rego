# METADATA
# title: Required cost tags
# description: Every created or updated AWS resource that supports tags must carry the FinOps tag keys
# entrypoint: true
package terraform.tags

import rego.v1

# Layer 2 of 4: gate the plan in CI. Input is `terraform show -json <planfile>`.
# Override the keys with conftest --data, e.g. {"finops": {"required_tags": [...]}}.
default_required := {"owner", "cost-center", "environment"}

required := {k | some k in data.finops.required_tags} if data.finops.required_tags

else := default_required

deny contains msg if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
	startswith(rc.type, "aws_")
	tags := _tags(rc.change.after)
	missing := {k | some k in required; not _has_value(tags, k)}
	count(missing) > 0
	msg := sprintf("%s is missing required tags: %v", [rc.address, sort(missing)])
}

# tags_all includes the provider's default_tags; fall back to tags. A resource
# type with neither attribute does not support tagging and is skipped.
_tags(after) := after.tags_all if after.tags_all

else := after.tags if after.tags

_has_value(tags, k) if {
	v := tags[k]
	trim_space(v) != ""
}
