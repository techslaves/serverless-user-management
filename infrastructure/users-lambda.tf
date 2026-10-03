# ── Package ───────────────────────────────────────────────────────────────────

resource "null_resource" "users_lambda_package" {
  triggers = {
    requirements = filemd5("${path.module}/../src/users/requirements.txt")
    source       = filemd5("${path.module}/../src/users/lambda_function.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/builds/users
      mkdir -p ${path.module}/builds/users
      cp ${path.module}/../src/users/*.py ${path.module}/builds/users/
      python3 -m pip install \
        -r ${path.module}/../src/users/requirements.txt \
        -t ${path.module}/builds/users/ \
        --upgrade \
        --quiet
    EOT
  }
}

data "archive_file" "users_lambda" {
  depends_on  = [null_resource.users_lambda_package]
  type        = "zip"
  source_dir  = "${path.module}/builds/users"
  output_path = "${path.module}/builds/users.zip"
}

# ── IAM role ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "users_lambda" {
  name = "${var.workshop_stack_base_name}-users-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-users-lambda-role" })
}

resource "aws_iam_policy" "users_lambda_dynamodb" {
  name        = "${var.workshop_stack_base_name}-users-lambda-dynamodb"
  description = "Least-privilege DynamoDB access for the users Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
      ]
      Resource = aws_dynamodb_table.users_table.arn
    }]
  })

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-users-lambda-dynamodb" })
}

resource "aws_iam_role_policy_attachment" "users_lambda_dynamodb" {
  role       = aws_iam_role.users_lambda.name
  policy_arn = aws_iam_policy.users_lambda_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "users_lambda_basic_execution" {
  role       = aws_iam_role.users_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "users_lambda_xray" {
  role       = aws_iam_role.users_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "users_lambda" {
  name              = "/aws/lambda/${var.workshop_stack_base_name}-users"
  retention_in_days = 30

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-users-logs" })
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "users" {
  function_name    = "${var.workshop_stack_base_name}-users"
  filename         = data.archive_file.users_lambda.output_path
  source_code_hash = data.archive_file.users_lambda.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  role             = aws_iam_role.users_lambda.arn
  memory_size      = 256
  timeout          = 30

  environment {
    variables = {
      USERS_TABLE_NAME = aws_dynamodb_table.users_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.users_lambda_basic_execution,
    aws_cloudwatch_log_group.users_lambda,
  ]

  tags = merge(local.tags, { Name = "${var.workshop_stack_base_name}-users" })
}

# ── API Gateway invoke permission ─────────────────────────────────────────────

resource "aws_lambda_permission" "users_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.users.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.users.execution_arn}/*/*"
}
