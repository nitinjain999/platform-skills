# METADATA
# title: Tests for S3 bucket encryption policy
package terraform.s3_test

import data.terraform.s3
import rego.v1

# --- deny: missing encryption resource ---

test_deny_missing_encryption if {
	count(s3.deny) == 1 with input as make_input("my-bucket", {}, null, null)
}

test_allow_with_encryption_resource if {
	count(s3.deny) == 0 with input as make_input(
		"my-bucket",
		{"acl": "private"},
		{"sse_algorithm": "aws:kms"},
		"Enabled",
	)
}

# --- deny: public ACL ---

test_deny_public_read_acl if {
	count(s3.deny) > 0 with input as make_input(
		"my-bucket",
		{"acl": "public-read"},
		{"sse_algorithm": "aws:kms"},
		"Enabled",
	)
}

test_deny_public_read_write_acl if {
	count(s3.deny) > 0 with input as make_input(
		"my-bucket",
		{"acl": "public-read-write"},
		{"sse_algorithm": "aws:kms"},
		"Enabled",
	)
}

test_allow_private_acl if {
	count(s3.deny) == 0 with input as make_input(
		"my-bucket",
		{"acl": "private"},
		{"sse_algorithm": "aws:kms"},
		"Enabled",
	)
}

# --- warn: missing versioning resource ---

test_warn_missing_versioning if {
	count(s3.warn) > 0 with input as make_input(
		"my-bucket",
		{"acl": "private"},
		{"sse_algorithm": "aws:kms"},
		null,
	)
}

test_no_warn_with_versioning if {
	count(s3.warn) == 0 with input as make_input(
		"my-bucket",
		{"acl": "private"},
		{"sse_algorithm": "aws:kms"},
		"Enabled",
	)
}

# Helper: build a Terraform HCL input shape matching AWS provider >= 5.
# enc_algo: SSE algorithm string (e.g. "aws:kms") or null to omit the resource.
# versioning_status: "Enabled"/"Suspended" or null to omit the resource.
make_input(bucket_name, extra_attrs, enc_algo, versioning_status) := input if {
	enc_algo != null
	versioning_status != null
	input := {
		"resource": {
			"aws_s3_bucket": {bucket_name: object.union({"bucket": bucket_name}, extra_attrs)},
			"aws_s3_bucket_server_side_encryption_configuration": {"enc": {
				"bucket": bucket_name,
				"rule": [{"apply_server_side_encryption_by_default": {"sse_algorithm": enc_algo}}],
			}},
			"aws_s3_bucket_versioning": {"ver": {
				"bucket": bucket_name,
				"versioning_configuration": [{"status": versioning_status}],
			}},
		},
	}
}

make_input(bucket_name, extra_attrs, enc_algo, versioning_status) := input if {
	enc_algo != null
	versioning_status == null
	input := {
		"resource": {
			"aws_s3_bucket": {bucket_name: object.union({"bucket": bucket_name}, extra_attrs)},
			"aws_s3_bucket_server_side_encryption_configuration": {"enc": {
				"bucket": bucket_name,
				"rule": [{"apply_server_side_encryption_by_default": {"sse_algorithm": enc_algo}}],
			}},
		},
	}
}

make_input(bucket_name, extra_attrs, enc_algo, versioning_status) := input if {
	enc_algo == null
	input := {"resource": {"aws_s3_bucket": {bucket_name: object.union({"bucket": bucket_name}, extra_attrs)}}}
}
