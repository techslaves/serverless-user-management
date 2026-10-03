# Source — Lambda Functions

Python 3.10 source code for the two Lambda functions that power the Serverless Users Service.

## Directory Structure

```
src/
├── authorizer/
│   ├── lambda_authorizer.py   # JWT validation + IAM policy generation
│   └── requirements.txt       # PyJWT==2.9.0, requests==2.32.3
└── users/
    ├── lambda_function.py     # HTTP routing + request/response handling
    ├── db.py                  # Standalone DynamoDB operations module
    └── requirements.txt       # boto3
```

---

## `authorizer/` — Lambda Authorizer

**Function name:** `workshop-authorizer`  
**Handler:** `lambda_authorizer.handler`  
**Trigger:** API Gateway TOKEN authorizer — called before every non-OPTIONS request

### How it works

```
API Gateway
    │  Authorization: Bearer <token>
    ▼
handler()
    │
    ├── Strip "Bearer " prefix
    ├── jwt.get_unverified_header(token) → extract kid
    ├── _get_jwks() → fetch/cache JWKS from Cognito
    ├── Match kid against JWKS keys
    ├── Validate claims (iss, client_id, token_use == "access")
    │
    ├── OK  → _build_policy(sub, "Allow")  + context {sub, email, username}
    └── ERR → _build_policy("anonymous", "Deny")
```

### Key functions

| Function | Description |
|----------|-------------|
| `handler(event, context)` | Entry point — extracts token, calls `_validate_token`, returns IAM policy |
| `_validate_token(token)` | Decodes JWT header, matches `kid` against JWKS, validates `iss`/`client_id`/`token_use` claims |
| `_get_jwks()` | Fetches JWKS from Cognito's well-known endpoint; result cached in `_jwks_cache` for the lifetime of the execution environment |
| `_build_policy(principal_id, effect, resource)` | Builds a minimal IAM policy document granting or denying `execute-api:Invoke` |

### Authorizer context

On a successful `Allow`, the following values are injected into `requestContext.authorizer` and are available to the downstream Users Lambda:

| Key | Source claim |
|-----|-------------|
| `sub` | `sub` (Cognito user UUID) |
| `email` | `email` |
| `username` | `username` or `cognito:username` |

### Environment variables

| Variable | Description |
|----------|-------------|
| `USER_POOL_ID` | Cognito User Pool ID — used to build the issuer URL and JWKS endpoint |
| `CLIENT_ID` | Cognito App Client ID — validated against the `client_id` claim |
| `AWS_REGION` | Injected by Lambda runtime (defaults to `us-east-1` if absent) |

### Dependencies (`requirements.txt`)

| Package | Version | Purpose |
|---------|---------|---------|
| `PyJWT` | 2.9.0 | JWT decode and header parsing |
| `requests` | 2.32.3 | HTTP GET to Cognito JWKS endpoint |

### Important note — signature verification

`_validate_token` intentionally uses `verify_signature: False` (workshop simplification). In a production authorizer you would pass the matched RSA public key from the JWKS to `jwt.decode()` so the signature is cryptographically verified.

---

## `users/` — Users Lambda

**Function name:** `workshop-users`  
**Handler:** `lambda_function.lambda_handler`  
**Trigger:** API Gateway proxy integration (all `/users` and `/users/{userid}` routes)

### How it works

```
API Gateway (AWS_PROXY)
    │
    ▼
lambda_handler(event, context)
    │
    ├── OPTIONS → return 200 + CORS headers (preflight)
    │
    └── Lookup (httpMethod, resource) in _ROUTES dispatch table
            │
            ├── GET    /users             → _handle_list_users
            ├── POST   /users             → _handle_create_user
            ├── GET    /users/{userid}    → _handle_get_user
            ├── PUT    /users/{userid}    → _handle_update_user
            └── DELETE /users/{userid}   → _handle_delete_user
```

### `lambda_function.py` — routing and HTTP layer

**Route dispatch table**

```python
_ROUTES = {
    ("GET",    "/users"):          _handle_list_users,
    ("POST",   "/users"):          _handle_create_user,
    ("GET",    "/users/{userid}"): _handle_get_user,
    ("PUT",    "/users/{userid}"): _handle_update_user,
    ("DELETE", "/users/{userid}"): _handle_delete_user,
}
```

Keyed on `(httpMethod, resource)` from the API Gateway proxy event. Adding a new route is a one-line change in this table.

**Response helpers**

All responses share a common structure built by `_response(status_code, body)`:

```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS"
  },
  "body": "<JSON string>"
}
```

**Route handlers**

| Handler | Method + Path | Validation | Success | Error |
|---------|--------------|------------|---------|-------|
| `_handle_list_users` | `GET /users` | — | `200` list | — |
| `_handle_create_user` | `POST /users` | `first_name`, `last_name`, `email` all required | `201` created user | `400` missing field |
| `_handle_get_user` | `GET /users/{userid}` | — | `200` user | `404` not found |
| `_handle_update_user` | `PUT /users/{userid}` | At least one of `first_name`, `last_name`, `email` | `200` updated user | `400` empty body / `404` not found |
| `_handle_delete_user` | `DELETE /users/{userid}` | — | `200` confirmation message | `404` not found |

**Error handling**

- `ConditionalCheckFailedException` from DynamoDB → `404`
- Any `ClientError` → `500`
- Unexpected exceptions → `500`

### `db.py` — DynamoDB operations module

A standalone data-access module that exposes clean public functions. It can be imported independently for testing or reuse without bringing in the HTTP layer.

**Functions**

| Function | DynamoDB call | Notes |
|----------|--------------|-------|
| `scan_users() → list` | `Table.scan()` | Returns all items; no pagination — suitable for small tables |
| `create_user(first_name, last_name, email) → dict` | `Table.put_item()` | Generates a UUID v4 for `userid`; uses `ConditionExpression` to prevent overwriting an existing item |
| `get_user(userid) → dict \| None` | `Table.get_item()` | Returns `None` if not found |
| `update_user(userid, updates) → dict` | `Table.update_item()` | Builds `SET` expression dynamically from `updates` dict; raises `UserNotFoundError` if item doesn't exist; returns full updated item via `ReturnValues="ALL_NEW"` |
| `delete_user(userid) → None` | `Table.delete_item()` | Raises `UserNotFoundError` if item doesn't exist |

**`UserNotFoundError`**

A domain-specific exception raised by `update_user` and `delete_user` when the DynamoDB `ConditionExpression` (`Attr("userid").exists()`) fails. Callers can catch this to return a clean `404` instead of leaking a boto3 `ClientError`.

**Environment variables**

| Variable | Description |
|----------|-------------|
| `USERS_TABLE_NAME` | DynamoDB table name — injected by Terraform via the Lambda `environment` block |

**Dependencies (`requirements.txt`)**

| Package | Purpose |
|---------|---------|
| `boto3` | AWS SDK — DynamoDB resource client |

### User data model

| Field | Type | Set by |
|-------|------|--------|
| `userid` | String (UUID v4) | Auto-generated on create |
| `first_name` | String | Required on create; updatable |
| `last_name` | String | Required on create; updatable |
| `email` | String | Required on create; updatable |

---

## Local development

### Running tests

```bash
pip install pytest moto boto3
pytest tests/unit -v
```

Tests use [moto](https://github.com/getmoto/moto) to mock DynamoDB — no AWS credentials needed.

### Installing dependencies locally

```bash
pip install -r src/authorizer/requirements.txt
pip install -r src/users/requirements.txt
```

### Invoking the users Lambda locally (with SAM or a test event)

```bash
# Minimal create-user test event
python - <<'EOF'
import json, os
os.environ["USERS_TABLE_NAME"] = "workshop_users"
from src.users.lambda_function import lambda_handler
event = {
    "httpMethod": "POST",
    "resource": "/users",
    "body": json.dumps({"first_name": "Jane", "last_name": "Doe", "email": "jane@example.com"}),
    "pathParameters": None,
}
print(json.dumps(lambda_handler(event, None), indent=2))
EOF
```
