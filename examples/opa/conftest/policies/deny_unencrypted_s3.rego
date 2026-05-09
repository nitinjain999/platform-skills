# METADATA
# title: S3 bucket encryption
# description: S3 buckets must have server-side encryption enabled and must not use public ACLs
# authors:
# - Platform Team <platform@example.com>
# entrypoint: true
package terraform.s3

import rego.v1

deny contains msg if {
	some name
	bucket := input.resource.aws_s3_bucket[name]
	not bucket.server_side_encryption_configuration
	msg := sprintf("S3 bucket '%s' must have server_side_encryption_configuration", [name])
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

warn contains msg if {
	some name
	_ = input.resource.aws_s3_bucket[name]
	not input.resource.aws_s3_bucket_versioning
	msg := sprintf("S3 bucket '%s' should have versioning enabled", [name])
}
