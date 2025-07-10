output "website_url" {
  description = "S3 website endpoint"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "website_domain" {
  description = "S3 website domain"
  value       = aws_s3_bucket_website_configuration.website.website_domain
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.website.id
}

output "api_gateway_url" {
  description = "API Gateway URL for visitor counter"
  value       = "${aws_api_gateway_deployment.visitor_deployment.invoke_url}/visitor-count"
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for visitor counter"
  value       = aws_dynamodb_table.visitor_counter.name
}

output "lambda_function_name" {
  description = "Lambda function name for visitor counter"
  value       = aws_lambda_function.visitor_counter.function_name
}

output "certificate_arn" {
  description = "ACM certificate ARN (if domain is configured)"
  value       = var.domain_name != "" ? aws_acm_certificate.website[0].arn : "No domain configured"
}

output "route53_nameservers" {
  description = "Route 53 nameservers (if new zone is created)"
  value       = var.domain_name != "" && var.create_route53_zone ? aws_route53_zone.website[0].name_servers : []
}
