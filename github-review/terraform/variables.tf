variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "bedrock-infra-generator"
}

variable "context_key" {
  description = "S3 object key for the organizational context/tags file"
  type        = string
  default     = "it-operations-tags.json"
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock model ID for code generation"
  type        = string
  default     = "us.anthropic.claude-sonnet-4-20250514-v1:0"
}

variable "github_token" {
  description = "GitHub personal access token for PR creation"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub repository owner (username or org)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for Terraform code PRs"
  type        = string
}
