# Serverless Users Service

A serverless REST API for user management built with AWS Lambda, API Gateway, DynamoDB, and Cognito, provisioned entirely with Terraform.

## Architecture

```
Client
  │
  │  Bearer <access_token>
  ▼
┌─────────────────────────┐
│   Amazon API Gateway    │  REST API (v1 stage)
│   (workshop-users-api)  │
└────────────┬────────────┘
             │  TOKEN authorizer on every non-OPTIONS route
             ▼
┌─────────────────────────┐
│  Lambda Authorizer      │  workshop-authorizer
│  (lambda_authorizer.py) │  • Fetches JWKS from Cognito
│                         │  • Validates iss, client_id, token_use
│                         │  • Returns Allow/Deny IAM policy
└────────────┬────────────┘
             │  Allow → invoke users Lambda
             ▼
┌─────────────────────────┐      ┌──────────────────────┐
│  Users Lambda           │─────▶│  DynamoDB            │
│  (lambda_function.py)   │      │  workshop_users      │
│  GET/POST /users        │      │  PK: userid (String) │
│  GET/PUT/DELETE         │      └──────────────────────┘
│  /users/{userid}        │
└─────────────────────────┘

┌─────────────────────────┐
│  Amazon Cognito         │  Hosted UI + token issuer
│  User Pool              │  • Self-registration enabled
│  App Client (no secret) │  • OAuth2 authorization code flow
│  Hosted UI domain       │  • Access tokens (1 hr), refresh (30 days)
└─────────────────────────┘
```

## Directory Structure

```
.
├── infrastructure/          # Terraform configuration
│   ├── api-gateway.tf       # REST API, methods, deployment, stage
│   ├── cognito.tf           # User pool, app client, domain, admin group
│   ├── dynamodb.tf          # Users DynamoDB table
│   ├── lambda-authorizer.tf # Authorizer Lambda + IAM + API Gateway authorizer resource
│   ├── users-lambda.tf      # Users Lambda + IAM + packaging
│   ├── outputs.tf           # Stack outputs
│   ├── variables.tf         # Input variables
│   ├── provider.tf          # AWS provider (us-west-2)
│   └── versions.tf          # Terraform version constraint
├── src/
│   ├── authorizer/
│   │   ├── lambda_authorizer.py   # JWT validation + IAM policy generation
│   │   └── requirements.txt       # PyJWT, requests
│   └── users/
│       ├── lambda_function.py     # HTTP routing + request/response handling
│       ├── db.py                  # DynamoDB operations
│       └── requirements.txt       # boto3
└── tests/
    └── unit/
        ├── conftest.py            # moto fixtures
        └── test_users_handler.py  # Unit tests for all CRUD routes
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured for `us-west-2`
- Python 3.10 (for local packaging during `terraform apply`)

## Deploy

```bash
cd infrastructure
terraform init
terraform apply -auto-approve
```

Terraform packages both Lambda functions (running `pip install` locally into `builds/`), creates all AWS resources, and prints the stack outputs on completion.

## Stack Outputs

| Output | Description |
|--------|-------------|
| `api_gateway_url` | Base URL for the Users API |
| `cognito_login_url` | Hosted UI login URL (authorization code flow) |
| `cognito_user_pool_id` | Cognito User Pool ID |
| `cognito_user_pool_client_id` | App client ID |
| `cognito_issuer_url` | JWT issuer URL for token verification |
| `cognito_admin_group_name` | Name of the Administrators group |
| `cognito_sample_auth_command` | Ready-to-run AWS CLI auth command |
| `authorizer_lambda_arn` | ARN of the Lambda authorizer function |
| `users_lambda_arn` | ARN of the users Lambda function |
| `users_table_name` | DynamoDB table name |

## Authentication

The API uses a Lambda TOKEN authorizer. Every request (except CORS preflight `OPTIONS`) requires a valid Cognito **access token** in the `Authorization` header.

### Option A — Hosted UI (browser)

1. Open the `cognito_login_url` output in a browser
2. Sign up or sign in
3. After redirect to `http://localhost:3000/callback?code=<code>`, copy the `code` value
4. Exchange it for tokens:

```bash
curl -X POST \
  "https://<domain>.auth.us-west-2.amazoncognito.com/oauth2/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&client_id=<client_id>&code=<code>&redirect_uri=http://localhost:3000/callback"
```

### Option B — AWS CLI (USER_PASSWORD_AUTH)

```bash
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=<email>,PASSWORD=<password> \
  --client-id <cognito_user_pool_client_id> \
  --region us-west-2 \
  --query 'AuthenticationResult.AccessToken' \
  --output text
```

Use the returned access token as `Authorization: Bearer <token>` on all API requests.

## API Endpoints

All endpoints require `Authorization: Bearer <access_token>` except OPTIONS.

### List users
```
GET /users
```
```bash
curl -H "Authorization: Bearer <token>" <api_gateway_url>
```
Response `200`:
```json
[
  { "userid": "uuid", "first_name": "Jane", "last_name": "Doe", "email": "jane@example.com" }
]
```

### Create user
```
POST /users
```
```bash
curl -X POST <api_gateway_url> \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"first_name": "Jane", "last_name": "Doe", "email": "jane@example.com"}'
```
Response `201`:
```json
{ "userid": "uuid", "first_name": "Jane", "last_name": "Doe", "email": "jane@example.com" }
```

### Get user
```
GET /users/{userid}
```
```bash
curl -H "Authorization: Bearer <token>" <api_gateway_url>/<userid>
```
Response `200` or `404`.

### Update user
```
PUT /users/{userid}
```
```bash
curl -X PUT <api_gateway_url>/<userid> \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"email": "new@example.com"}'
```
Accepts any subset of `first_name`, `last_name`, `email`. Response `200` or `404`.

### Delete user
```
DELETE /users/{userid}
```
```bash
curl -X DELETE -H "Authorization: Bearer <token>" <api_gateway_url>/<userid>
```
Response `200` or `404`.

## Lambda Authorizer

`src/authorizer/lambda_authorizer.py` implements a TOKEN authorizer:

1. Strips `Bearer ` prefix from the `Authorization` header
2. Decodes the JWT header to extract `kid`
3. Fetches JWKS from `https://cognito-idp.us-west-2.amazonaws.com/<pool_id>/.well-known/jwks.json` (cached per execution environment)
4. Confirms the `kid` exists in the JWKS (token was issued by this user pool's key)
5. Validates claims: `iss`, `client_id`, `token_use == "access"`
6. Returns an IAM `Allow` policy with `sub`, `email`, and `username` in the context (available to the downstream Lambda via `requestContext.authorizer`)
7. Returns an IAM `Deny` policy on any failure

Results are cached by API Gateway for 5 minutes (`authorizer_result_ttl_in_seconds = 300`).

## Running Tests

```bash
cd tests/unit
pip install pytest moto boto3
pytest -v
```

Tests use [moto](https://github.com/getmoto/moto) to mock DynamoDB — no AWS credentials or live resources required.

## Tear Down

```bash
cd infrastructure
terraform destroy -auto-approve
```

## Resource Tagging

All resources are tagged:

| Tag | Value |
|-----|-------|
| `Environment` | `Workshop` |
| `Project` | `Serverless Patterns` |
| `Name` | Resource-specific name |
