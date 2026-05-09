resource "aws_s3_bucket" "good_bucket" {
  bucket = "my-app-data-encrypted"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "arn:aws:kms:eu-central-1:123456789012:key/abc"
      }
    }
  }
}

# This bucket should trigger deny rules
resource "aws_s3_bucket" "bad_bucket" {
  bucket = "my-public-data"
  acl    = "public-read"
}
