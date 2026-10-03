# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "user_pool_admin_group_name" {
  description = "Name for the admin group in Cognito User Pool"
  type        = string
  default     = "Administrators"
}

# 1. AWS Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.workshop_stack_base_name}-user-pool"

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  auto_verified_attributes = ["email"]

  schema {
    name                = "name"
    attribute_data_type = "String"
    mutable             = true
    required            = true
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
  }

  username_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  lifecycle {
    ignore_changes = [schema]
  }

  tags = {
    Name        = "${var.workshop_stack_base_name}-user-pool"
    Environment = "Workshop"
    Project     = "Serverless Patterns"
  }
}

# 2. Cognito User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.workshop_stack_base_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH"
  ]

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  refresh_token_validity               = 30
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid"]
  callback_urls                        = ["http://localhost:3000/callback"]
}

# 3. Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = aws_cognito_user_pool_client.client.id
  user_pool_id = aws_cognito_user_pool.main.id
}

# 4. Cognito User Group for administrators
resource "aws_cognito_user_group" "admin" {
  name         = var.user_pool_admin_group_name
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "API Administrators"
  precedence   = 0
}

# 5. API Gateway Cognito Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.workshop_stack_base_name}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.users.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  identity_source = "method.request.header.Authorization"
}
