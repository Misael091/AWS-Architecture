output "vpc_id" {
  description = "ID of the main VPC"
  value       = aws_vpc.main.id
}

output "dev_api_endpoint" {
  description = "HTTP API Gateway endpoint for Dev"
  value       = aws_apigatewayv2_api.dev.api_endpoint
}

output "prod_api_endpoint" {
  description = "HTTP API Gateway endpoint for Prod"
  value       = aws_apigatewayv2_api.prod.api_endpoint
}

output "s3_bucket_name" {
  description = "Private S3 bucket name for PDF storage"
  value       = aws_s3_bucket.pdf_storage.id
}
