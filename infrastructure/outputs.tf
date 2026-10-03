output "users_table_name" {
  description = "DynamoDB table name for the Users service"
  value       = aws_dynamodb_table.users_table.name
}

output "users_table_arn" {
  description = "DynamoDB table ARN for the Users service"
  value       = aws_dynamodb_table.users_table.arn
}

output "users_table_id" {
  description = "DynamoDB table ID for the Users service"
  value       = aws_dynamodb_table.users_table.id
}

output "users_lambda_arn" {
  description = "ARN of the users Lambda function"
  value       = aws_lambda_function.users.arn
}

output "users_lambda_function_name" {
  description = "Name of the users Lambda function"
  value       = aws_lambda_function.users.function_name
}

output "users_lambda_invoke_arn" {
  description = "Invoke ARN of the users Lambda function (used by API Gateway)"
  value       = aws_lambda_function.users.invoke_arn
}

output "api_gateway_url" {
  description = "Base URL for the Users API"
  value       = "${aws_api_gateway_stage.users.invoke_url}/users"
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito App Client ID (public, no secret)"
  value       = aws_cognito_user_pool_client.client.id
}

output "cognito_issuer_url" {
  description = "JWT issuer URL for token verification"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "cognito_admin_group_name" {
  description = "Name of the Cognito Administrators group"
  value       = aws_cognito_user_group.admin.name
}

output "cognito_login_url" {
  description = "Hosted UI login URL (requires domain to be provisioned)"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.client.id}&response_type=code&scope=email+openid&redirect_uri=http://localhost:3000/callback"
}

output "cognito_sample_auth_command" {
  description = "Sample AWS CLI command to authenticate with USER_PASSWORD_AUTH"
  value       = "aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --auth-parameters USERNAME=<your-email>,PASSWORD=<your-password> --client-id ${aws_cognito_user_pool_client.client.id} --region ${var.region} --query 'AuthenticationResult.IdToken' --output text"
}
