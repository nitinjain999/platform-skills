output "web_acl_arn" {
  description = "ARN of the WAF WebACL. Pass this to var.waf_web_acl_arn in the CloudFront module."
  value       = aws_wafv2_web_acl.cloudfront.arn
}

output "web_acl_id" {
  description = "ID of the WAF WebACL."
  value       = aws_wafv2_web_acl.cloudfront.id
}

output "web_acl_capacity" {
  description = "Current WCU (Web ACL Capacity Unit) consumption. Max per WebACL is 5000."
  value       = aws_wafv2_web_acl.cloudfront.capacity
}

output "log_group_name" {
  description = "CloudWatch log group name for WAF logs."
  value       = aws_cloudwatch_log_group.waf.name
}

output "log_group_arn" {
  description = "CloudWatch log group ARN for WAF logs."
  value       = aws_cloudwatch_log_group.waf.arn
}
