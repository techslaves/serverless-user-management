# Infrastructure — Serverless Users Service

Terraform configuration for the Workshop Serverless Users Service. Provisions a fully serverless REST API on AWS using API Gateway, Lambda, DynamoDB, and Cognito.

## Architecture Overview

```
Client
  │
  ▼
API Gateway (REST — stage: v1)
  │
  ├── Lambda Authorizer ──► Cognito User Pool (JWT validation)
  │
  └── Users Lambda ──► DynamoDB (workshop_users table)
```

All API routes (except OPTIONS) are protected by a Lambda TOKEN authorizer that validates Cognito-issued JWTs.

## API Routes

| Method   | Path               | Description            |
|----------|--------------------|------------------------|
| `GET`    | `/users`           | List all users         |
| `POST`   | `/users`           | Create a user          |
| `GET`    | `/users/{userid}`  | Get a user by ID       |
| `PUT`    | `/users/{userid}`  | Update a user          |
| `DELETE` | `/users/{userid}`  | Delete a user          |
| `OPTIONS`| `/users`           | CORS preflight         |
| `OPTIONS`| `/users/{userid}`  | CORS preflight         |

## Terraform Files

| File | Resources |
|------|-----------|
| `provider.tf` | AWS provider configuration |
| `versions.tf` | Terraform version constraint (`>= 1.0.0`) |
| `variables.tf` | Input variables (region, base name, tags) |
| `ddb.tf` | DynamoDB table, locals (shared tags) |
| `dynamodb.tf` | _(empty — reserved)_ |
| `cognito.tf` | Cognito User Pool, App Client, Domain, Admin group, Cognito authorizer resource |
| `lambda-authorizer.tf` | Authorizer Lambda: build, IAM role, log group, function, API Gateway permission, TOKEN authorizer |
| `users-lambda.tf` | Users Lambda: build, IAM role + DynamoDB policy, log group, function, API Gateway permission |
| `api-gateway.tf` | REST API, `/users` and `/users/{userid}` resources + methods, deployment, stage (v1), throttling, access logging |
| `outputs.tf` | Exported values: API URL, table name/ARN, Lambda ARNs, Cognito IDs, sample auth command |

## Module Details

### DynamoDB (`ddb.tf`)

- **Table name:** `workshop_users`
- **Billing:** PAY_PER_REQUEST (on-demand)
- **Hash key:** `userid` (String)
- **Encryption:** Server-side encryption enabled
- **Backups:** Point-in-time recovery enabled

### Cognito (`cognito.tf`)

- **User Pool:** email as username, email auto-verified
- **Password policy:** min 8 chars, requires upper/lower/number/symbol
- **App Client:** supports `USER_PASSWORD_AUTH`, `USER_SRP_AUTH`, `ADMIN_USER_PASSWORD_AUTH`, `REFRESH_TOKEN_AUTH`; no client secret
- **OAuth:** authorization code flow, scopes: `email openid`, callback: `http://localhost:3000/callback`
- **Admin group:** `Administrators` (precedence 0)
- **Cognito Authorizer:** defined but routes currently use the Lambda authorizer

### Lambda Authorizer (`lambda-authorizer.tf`)

- **Function name:** `workshop-authorizer`
- **Handler:** `lambda_authorizer.handler`
- **Runtime:** Python 3.10 — 128 MB, 10 s timeout
- **Authorization type:** TOKEN (reads `Authorization` header)
- **TTL:** 300 s (policy cached per token)
- **IAM:** `AWSLambdaBasicExecutionRole` only
- **Build:** Dependencies installed from `src/authorizer/requirements.txt` into `builds/authorizer/`, zipped by `archive_file`; rebuild triggered on source or requirements change

### Users Lambda (`users-lambda.tf`)

- **Function name:** `workshop-users`
- **Handler:** `lambda_function.lambda_handler`
- **Runtime:** Python 3.10 — 256 MB, 30 s timeout
- **X-Ray tracing:** Active
- **Environment variable:** `USERS_TABLE_NAME`
- **IAM:** `AWSLambdaBasicExecutionRole` + `AWSXRayDaemonWriteAccess` + least-privilege inline policy for `dynamodb:GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Scan` on the users table only
- **Build:** Same pip-install pattern as the authorizer; rebuild triggered on source or requirements change

### API Gateway (`api-gateway.tf`)

- **Stage:** `v1`
- **Access logging:** JSON format to CloudWatch (`/aws/apigateway/workshop-users-api`), 30-day retention
- **Throttling:** burst 50 / rate 100 (applied to all methods via `*/*`)
- **Deployment trigger:** SHA1 hash of all method and authorizer IDs — auto-redeploys on any route change
- **CloudWatch role:** account-level role attached so API Gateway can push access logs

## Variables

| Name | Default | Description |
|------|---------|-------------|
| `region` | `us-west-2` | AWS region to deploy into |
| `workshop_stack_base_name` | `workshop` | Prefix used for all resource names |
| `environment` | `Workshop` | Value for the `Environment` tag |
| `project` | `Serverless Patterns` | Value for the `Project` tag |

## Outputs

| Output | Description |
|--------|-------------|
| `api_gateway_url` | Base URL for the API (`https://<id>.execute-api.us-west-2.amazonaws.com/v1/users`) |
| `users_table_name` | DynamoDB table name |
| `users_table_arn` | DynamoDB table ARN |
| `users_lambda_arn` | ARN of the users Lambda function |
| `users_lambda_function_name` | Name of the users Lambda function |
| `users_lambda_invoke_arn` | Invoke ARN used by API Gateway integration |
| `authorizer_lambda_arn` | ARN of the Lambda authorizer function |
| `cognito_user_pool_id` | Cognito User Pool ID |
| `cognito_user_pool_client_id` | App Client ID (public — no secret) |
| `cognito_issuer_url` | JWT issuer URL for token verification |
| `cognito_admin_group_name` | Name of the Cognito Administrators group |
| `cognito_login_url` | Hosted UI login URL |
| `cognito_sample_auth_command` | Sample `aws cognito-idp initiate-auth` CLI command |

## Requirements

- Terraform >= 1.0.0
- Python 3.x and `pip` available locally (used by the Lambda build provisioners)
- AWS credentials configured for `us-west-2`

## Usage

```bash
cd infrastructure

terraform init
terraform plan
terraform apply
```

After apply, retrieve the API URL:

```bash
terraform output api_gateway_url
```

Authenticate via Cognito and call the API:

```bash
# Get an ID token
TOKEN=$(terraform output -raw cognito_sample_auth_command | bash)

# List users
curl -H "Authorization: $TOKEN" $(terraform output -raw api_gateway_url)
```