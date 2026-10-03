# ── Package ───────────────────────────────────────────────────────────────────

resource "null_resource" "authorizer_lambda_package" {
  triggers = {
    requirements = filemd5("${path.module}/../src/authorizer/requirements.txt")
    source       = filemd5("${path.module}/../src/authorizer/lambda_authorizer.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/builds/authorizer
      mkdir -p ${path.module}/builds/authorizer
      cp ${path.module}/../src/authorizer/*.py ${path.module}/builds/authorizer/
      python3 -m pip install \
        -r ${path.module}/../src/authorizer/requirements.txt \
        -t ${path.module}/builds/authorizer/ \
        --upgrade \
        --quiet
    EOT
  }
}

data "archive_file" "authorizer_lambda" {
  depends_on  = [null_resource.authorizer_lambda_package]
  type        = "zip"
  source_dir  = "${path.module}/builds/authorizer"
  output_path = "${path.module}/builds/authorizer.zip"
}

# ── IAM role ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "authorizer_lambda" {
  name = "${var.workshop_stack_base_name}-authorizer-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-authorizer-lambda-role" })
}

resource "aws_iam_role_policy_attachment" "authorizer_lambda_basic_execution" {
  role       = aws_iam_role.authorizer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "authorizer_lambda" {
  name              = "/aws/lambda/${var.workshop_stack_base_name}-authorizer"
  retention_in_days = 30

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-authorizer-logs" })
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.workshop_stack_base_name}-authorizer"
  filename         = data.archive_file.authorizer_lambda.output_path
  source_code_hash = data.archive_file.authorizer_lambda.output_base64sha256
  handler          = "lambda_authorizer.handler"
  runtime          = "python3.10"
  role             = aws_iam_role.authorizer_lambda.arn
  memory_size      = 128
  timeout          = 10

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.main.id
      CLIENT_ID    = aws_cognito_user_pool_client.client.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.authorizer_lambda_basic_execution,
    aws_cloudwatch_log_group.authorizer_lambda,
  ]

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-authorizer" })
}

# ── API Gateway invoke permission ─────────────────────────────────────────────

resource "aws_lambda_permission" "authorizer_api_gateway" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.users.execution_arn}/*/*"
}

# ── API Gateway Token Authorizer ──────────────────────────────────────────────

resource "aws_api_gateway_authorizer" "lambda" {
  name                             = "${var.workshop_stack_base_name}-lambda-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.users.id
  type                             = "TOKEN"
  authorizer_uri                   = aws_lambda_function.authorizer.invoke_arn
  identity_source                  = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300
}

# ── Output ────────────────────────────────────────────────────────────────────

output "authorizer_lambda_arn" {
  description = "ARN of the Lambda authorizer function"
  value       = aws_lambda_function.authorizer.arn
}
