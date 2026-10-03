# ── Account-level CloudWatch Logs role (required for access logging) ──────────

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${var.workshop_stack_base_name}-apigw-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-apigw-cloudwatch-role" })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn

  depends_on = [aws_iam_role_policy_attachment.api_gateway_cloudwatch]
}

# ── REST API ──────────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "users" {
  name        = "${var.workshop_stack_base_name}-users-api"
  description = "Users CRUD API"

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-users-api" })
}

# ── Resources ─────────────────────────────────────────────────────────────────

resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.users.id
  parent_id   = aws_api_gateway_rest_api.users.root_resource_id
  path_part   = "users"
}

resource "aws_api_gateway_resource" "user" {
  rest_api_id = aws_api_gateway_rest_api.users.id
  parent_id   = aws_api_gateway_resource.users.id
  path_part   = "{userid}"
}

# ── /users methods ────────────────────────────────────────────────────────────

resource "aws_api_gateway_method" "users_get" {
  rest_api_id   = aws_api_gateway_rest_api.users.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
}

resource "aws_api_gateway_integration" "users_get" {
  rest_api_id             = aws_api_gateway_rest_api.users.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.users_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users.invoke_arn
}

resource "aws_api_gateway_method" "users_post" {
  rest_api_id   = aws_api_gateway_rest_api.users.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
}

resource "aws_api_gateway_integration" "users_post" {
  rest_api_id             = aws_api_gateway_rest_api.users.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.users_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users.invoke_arn
}

resource "aws_api_gateway_method" "users_options" {
  rest_api_id   = aws_api_gateway_rest_api.users.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "users_options" {
  rest_api_id             = aws_api_gateway_rest_api.users.id
  resource_id             = aws_api_gateway_resource.users.id
  http_method             = aws_api_gateway_method.users_options.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users.invoke_arn
}

# ── /users/{userid} methods ───────────────────────────────────────────────────

resource "aws_api_gateway_method" "user_get" {
  rest_api_id   = aws_api_gateway_rest_api.users.id
  resource_id   = aws_api_gateway_resource.user.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
}

resource "aws_api_gateway_integration" "user_get" {
  rest_api_id             = aws_api_gateway_rest_api.users.id
  resource_id             = aws_api_gateway_resource.user.id
  http_method             = aws_api_gateway_method.user_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users.invoke_arn
}

resource "aws_api_gateway_method" "user_put" {
  rest_api_id   = aws_api_gateway_rest_api.users.id
  resource_id   = aws_api_gateway_resource.user.id
  http_method   = "PUT"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
}

resource "aws_api_gateway_integration" "user_put" {
  rest_api_id             = aws_api_gateway_rest_api.users.id
  resource_id             = aws_api_gateway_resource.user.id
  http_method             = aws_api_gateway_method.user_put.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users.invoke_arn
}

resource "aws_api_gateway_method" "user_delete" {
  rest_api_id   = aws_api_gateway_rest_api.users.id
  resource_id   = aws_api_gateway_resource.user.id
  http_method   = "DELETE"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
}

resource "aws_api_gateway_integration" "user_delete" {
  rest_api_id             = aws_api_gateway_rest_api.users.id
  resource_id             = aws_api_gateway_resource.user.id
  http_method             = aws_api_gateway_method.user_delete.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users.invoke_arn
}

resource "aws_api_gateway_method" "user_options" {
  rest_api_id   = aws_api_gateway_rest_api.users.id
  resource_id   = aws_api_gateway_resource.user.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "user_options" {
  rest_api_id             = aws_api_gateway_rest_api.users.id
  resource_id             = aws_api_gateway_resource.user.id
  http_method             = aws_api_gateway_method.user_options.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users.invoke_arn
}

# ── Deployment & stage ────────────────────────────────────────────────────────

resource "aws_api_gateway_deployment" "users" {
  rest_api_id = aws_api_gateway_rest_api.users.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.users_get.id,
      aws_api_gateway_method.users_post.id,
      aws_api_gateway_method.users_options.id,
      aws_api_gateway_method.user_get.id,
      aws_api_gateway_method.user_put.id,
      aws_api_gateway_method.user_delete.id,
      aws_api_gateway_method.user_options.id,
      aws_api_gateway_authorizer.lambda.id,
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.users_get,
    aws_api_gateway_integration.users_post,
    aws_api_gateway_integration.users_options,
    aws_api_gateway_integration.user_get,
    aws_api_gateway_integration.user_put,
    aws_api_gateway_integration.user_delete,
    aws_api_gateway_integration.user_options,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.workshop_stack_base_name}-users-api"
  retention_in_days = 30

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-users-api-logs" })
}

resource "aws_api_gateway_stage" "users" {
  rest_api_id   = aws_api_gateway_rest_api.users.id
  deployment_id = aws_api_gateway_deployment.users.id
  stage_name    = "v1"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      ip             = "$context.identity.sourceIp"
      errorMessage   = "$context.error.message"
    })
  }

  depends_on = [
    aws_cloudwatch_log_group.api_gateway,
    aws_api_gateway_account.main,
  ]

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-users-api-v1" })
}

resource "aws_api_gateway_method_settings" "users" {
  rest_api_id = aws_api_gateway_rest_api.users.id
  stage_name  = aws_api_gateway_stage.users.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 100
  }
}
