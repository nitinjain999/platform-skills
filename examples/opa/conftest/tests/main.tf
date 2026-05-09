resource "aws_s3_bucket" "good_bucket" {
  bucket = "my-app-data-encrypted"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "good_bucket" {
  bucket = "my-app-data-encrypted"

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "arn:aws:kms:eu-central-1:123456789012:key/abc"
    }
  }
}

resource "aws_s3_bucket_versioning" "good_bucket" {
  bucket = "my-app-data-encrypted"

  versioning_configuration {
    status = "Enabled"
  }
}

# This bucket should trigger deny rules — no encryption resource, public ACL
resource "aws_s3_bucket" "bad_bucket" {
  bucket = "my-public-data"
  acl    = "public-read"
}
