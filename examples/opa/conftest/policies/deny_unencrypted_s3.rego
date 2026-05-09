# METADATA
# title: S3 bucket encryption
# description: S3 buckets must have server-side encryption enabled and must not use public ACLs
# authors:
# - Platform Team <platform@example.com>
# entrypoint: true
package terraform.s3

import rego.v1

# AWS provider >= 5 uses a separate aws_s3_bucket_server_side_encryption_configuration resource.
# Correlate it to the bucket by matching the "bucket" attribute.
deny contains msg if {
	some name
	_ = input.resource.aws_s3_bucket[name]
	not _bucket_has_encryption(name)
	msg := sprintf("S3 bucket '%s' must have an aws_s3_bucket_server_side_encryption_configuration resource", [name])
}

deny contains msg if {
	some name
	bucket := input.resource.aws_s3_bucket[name]
	bucket.acl == "public-read"
	msg := sprintf("S3 bucket '%s' must not use public-read ACL", [name])
}

deny contains msg if {
	some name
	bucket := input.resource.aws_s3_bucket[name]
	bucket.acl == "public-read-write"
	msg := sprintf("S3 bucket '%s' must not use public-read-write ACL", [name])
}

# Warn if no aws_s3_bucket_versioning resource references this specific bucket.
warn contains msg if {
	some name
	_ = input.resource.aws_s3_bucket[name]
	not _bucket_has_versioning(name)
	msg := sprintf("S3 bucket '%s' should have an aws_s3_bucket_versioning resource", [name])
}

_bucket_has_encryption(bucket_name) if {
	some enc_name
	enc := input.resource.aws_s3_bucket_server_side_encryption_configuration[enc_name]
	enc.bucket == bucket_name
}

_bucket_has_versioning(bucket_name) if {
	some ver_name
	ver := input.resource.aws_s3_bucket_versioning[ver_name]
	ver.bucket == bucket_name
}
