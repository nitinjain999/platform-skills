output "distribution_id" {
  description = "ID of the CloudFront distribution."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "ARN of the CloudFront distribution."
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain name (e.g. d1234.cloudfront.net). Use as CNAME target."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosted_zone_id" {
  description = "Route 53 hosted zone ID for the CloudFront distribution. Use with alias records."
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "origin_bucket_name" {
  description = "Name of the S3 origin bucket."
  value       = aws_s3_bucket.origin.bucket
}

output "origin_bucket_arn" {
  description = "ARN of the S3 origin bucket."
  value       = aws_s3_bucket.origin.arn
}

output "oac_id" {
  description = "ID of the CloudFront Origin Access Control."
  value       = aws_cloudfront_origin_access_control.this.id
}
