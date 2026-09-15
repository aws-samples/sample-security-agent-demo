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
  default     = "us.anthropic.claude-sonnet-5"
}

variable "aws_profile" {
  description = "AWS CLI profile name (omit to use default credentials)"
  type        = string
  default     = null
}

variable "default_tags" {
  description = "Default tags applied to all AWS resources"
  type        = map(string)
  default     = {}
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
