# METADATA
# title: Tests for S3 bucket encryption policy
package terraform.s3_test

import data.terraform.s3
import rego.v1

# --- deny: missing encryption resource ---

test_deny_missing_encryption if {
	count(s3.deny) == 1 with input as make_input_no_enc("my-bucket", {})
}

test_allow_with_encryption_resource if {
	count(s3.deny) == 0 with input as make_input_full("my-bucket", {"acl": "private"}, "aws:kms", "Enabled")
}

# --- deny: public ACL ---

test_deny_public_read_acl if {
	count(s3.deny) > 0 with input as make_input_full("my-bucket", {"acl": "public-read"}, "aws:kms", "Enabled")
}

test_deny_public_read_write_acl if {
	count(s3.deny) > 0 with input as make_input_full("my-bucket", {"acl": "public-read-write"}, "aws:kms", "Enabled")
}

test_allow_private_acl if {
	count(s3.deny) == 0 with input as make_input_full("my-bucket", {"acl": "private"}, "aws:kms", "Enabled")
}

# --- warn: missing versioning resource ---

test_warn_missing_versioning if {
	count(s3.warn) > 0 with input as make_input_enc_only("my-bucket", {"acl": "private"}, "aws:kms")
}

test_no_warn_with_versioning if {
	count(s3.warn) == 0 with input as make_input_full("my-bucket", {"acl": "private"}, "aws:kms", "Enabled")
}

# Helpers — build Terraform HCL input shapes matching AWS provider >= 5
# (encryption and versioning as separate resources, correlated by bucket name)

make_input_full(bucket_name, extra_attrs, enc_algo, versioning_status) := {"resource": {
	"aws_s3_bucket": {bucket_name: object.union({"bucket": bucket_name}, extra_attrs)},
	"aws_s3_bucket_server_side_encryption_configuration": {"enc": {
		"bucket": bucket_name,
		"rule": [{"apply_server_side_encryption_by_default": {"sse_algorithm": enc_algo}}],
	}},
	"aws_s3_bucket_versioning": {"ver": {
		"bucket": bucket_name,
		"versioning_configuration": [{"status": versioning_status}],
	}},
}}

make_input_enc_only(bucket_name, extra_attrs, enc_algo) := {"resource": {
	"aws_s3_bucket": {bucket_name: object.union({"bucket": bucket_name}, extra_attrs)},
	"aws_s3_bucket_server_side_encryption_configuration": {"enc": {
		"bucket": bucket_name,
		"rule": [{"apply_server_side_encryption_by_default": {"sse_algorithm": enc_algo}}],
	}},
}}

make_input_no_enc(bucket_name, extra_attrs) := {"resource": {"aws_s3_bucket": {bucket_name: object.union({"bucket": bucket_name}, extra_attrs)}}}
