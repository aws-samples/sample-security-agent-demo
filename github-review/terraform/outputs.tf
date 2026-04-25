output "api_gateway_url" {
  description = "API Gateway invocation URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/generate"
}

output "api_key" {
  description = "API key for authenticating requests"
  value       = aws_api_gateway_api_key.generator_key.value
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket for context storage"
  value       = aws_s3_bucket.context_bucket.bucket
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.infrastructure_generator.function_name
}