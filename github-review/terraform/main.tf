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

resource "aws_s3_bucket" "context_bucket" {
  bucket = "${var.project_name}-context-${random_id.bucket_suffix.hex}"

  # force_destroy lets `terraform destroy` remove the bucket even if it still
  # contains objects or prior versions. Essential here because versioning is
  # enabled below, and `terraform destroy` otherwise fails with BucketNotEmpty.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "context_bucket_versioning" {
  bucket = aws_s3_bucket.context_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_lambda_function" "infrastructure_generator" {
  filename         = "lambda_function.zip"
  function_name    = "${var.project_name}-infrastructure-generator"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = 300

  environment {
    variables = {
      CONTEXT_BUCKET  = aws_s3_bucket.context_bucket.bucket
      CONTEXT_KEY     = var.context_key
      BEDROCK_MODEL_ID = var.bedrock_model_id
      GITHUB_TOKEN    = var.github_token
      GITHUB_OWNER    = var.github_owner
      GITHUB_REPO     = var.github_repo
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.context_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:Converse"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "infrastructure_api" {
  name = "${var.project_name}-infrastructure-api"
}

resource "aws_api_gateway_resource" "generate" {
  rest_api_id = aws_api_gateway_rest_api.infrastructure_api.id
  parent_id   = aws_api_gateway_rest_api.infrastructure_api.root_resource_id
  path_part   = "generate"
}

resource "aws_api_gateway_method" "generate_post" {
  rest_api_id      = aws_api_gateway_rest_api.infrastructure_api.id
  resource_id      = aws_api_gateway_resource.generate.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.infrastructure_api.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.infrastructure_generator.invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.infrastructure_generator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.infrastructure_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_method.generate_post,
    aws_api_gateway_integration.lambda_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.infrastructure_api.id
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id        = aws_api_gateway_deployment.deployment.id
  rest_api_id          = aws_api_gateway_rest_api.infrastructure_api.id
  stage_name           = "prod"
  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

# CloudWatch log group for API Gateway access logs. Uses log-group-level access
# logging (configured directly on the stage) which does not depend on the
# account-wide aws_api_gateway_account CloudWatch role.
resource "aws_cloudwatch_log_group" "api_access_logs" {
  name              = "/aws/apigateway/${var.project_name}-access-logs"
  retention_in_days = 365
}

# API Key for securing the endpoint
resource "aws_api_gateway_api_key" "generator_key" {
  name    = "${var.project_name}-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "generator_plan" {
  name = "${var.project_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.infrastructure_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "generator_plan_key" {
  key_id        = aws_api_gateway_api_key.generator_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.generator_plan.id
}