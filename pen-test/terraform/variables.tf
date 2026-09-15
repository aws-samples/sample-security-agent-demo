variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "aws-security-agent-pentest"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "db_username" {
  description = "Database admin username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database admin password"
  type        = string
  sensitive   = true
  # Set via terraform.tfvars or TF_VAR_db_password environment variable
  # Example: export TF_VAR_db_password="YourStrongPassword123!"
}

variable "domain_name" {
  description = <<-EOT
    Route 53 hosted zone domain name for the pen test target (optional).

    If set to a non-empty value, Terraform will create a `pentest.<domain>` A
    record in the matching Route 53 hosted zone pointing to the ALB. The zone
    must already exist in this AWS account.

    If left as an empty string (the default), no DNS resources are created and
    you should use the `alb_dns_name` output as your pen test target.
  EOT
  type        = string
  default     = ""
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