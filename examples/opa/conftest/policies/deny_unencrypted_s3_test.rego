# METADATA
# title: Tests for S3 bucket encryption policy
package terraform.s3_test

import data.terraform.s3
import rego.v1

# --- deny: missing encryption ---

test_deny_missing_encryption if {
	count(s3.deny) == 1 with input as make_bucket("my-bucket", {})
}

test_allow_with_encryption if {
	count(s3.deny) == 0 with input as make_bucket("my-bucket", {
		"server_side_encryption_configuration": {"rule": {"apply_server_side_encryption_by_default": {"sse_algorithm": "aws:kms"}}},
		"acl": "private",
	})
}

# --- deny: public ACL ---

test_deny_public_read_acl if {
	count(s3.deny) > 0 with input as make_bucket("my-bucket", {
		"server_side_encryption_configuration": {"rule": {}},
		"acl": "public-read",
	})
}

test_deny_public_read_write_acl if {
	count(s3.deny) > 0 with input as make_bucket("my-bucket", {
		"server_side_encryption_configuration": {"rule": {}},
		"acl": "public-read-write",
	})
}

test_allow_private_acl if {
	count(s3.deny) == 0 with input as make_bucket("my-bucket", {
		"server_side_encryption_configuration": {"rule": {}},
		"acl": "private",
	})
}

# --- warn: missing versioning ---

test_warn_missing_versioning if {
	count(s3.warn) > 0 with input as make_bucket("my-bucket", {
		"server_side_encryption_configuration": {"rule": {}},
		"acl": "private",
	})
}

# Helper: build a minimal S3 bucket input
make_bucket(name, attrs) := {"resource": {"aws_s3_bucket": {name: attrs}}}
