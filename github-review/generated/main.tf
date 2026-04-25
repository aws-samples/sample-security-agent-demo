# Example generated Terraform — this file is sample output from the AI Infrastructure Generator.
# In practice, Bedrock generates this code and commits it via a GitHub PR.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

module "ec2" {
  source = "./ec2"
}

module "vpc" {
  source = "./vpc"
}
