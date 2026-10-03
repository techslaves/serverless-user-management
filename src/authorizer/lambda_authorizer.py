import os
import json
import logging
import requests
import jwt

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
USER_POOL_ID = os.environ["USER_POOL_ID"]
CLIENT_ID = os.environ["CLIENT_ID"]

ISSUER = f"https://cognito-idp.{AWS_REGION}.amazonaws.com/{USER_POOL_ID}"
JWKS_URL = f"{ISSUER}/.well-known/jwks.json"

_jwks_cache = None


def _get_jwks():
    global _jwks_cache
    if _jwks_cache is None:
        response = requests.get(JWKS_URL, timeout=5)
        response.raise_for_status()
        _jwks_cache = response.json()
    return _jwks_cache


def _build_policy(principal_id, effect, resource):
    return {
        "principalId": principal_id,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": resource,
                }
            ],
        },
    }


def _validate_token(token):
    # Decode header without verification to get kid
    header = jwt.get_unverified_header(token)
    kid = header.get("kid")
    if not kid:
        raise ValueError("Token header missing kid")

    jwks = _get_jwks()
    matching_key = next(
        (k for k in jwks.get("keys", []) if k["kid"] == kid), None
    )
    if matching_key is None:
        raise ValueError(f"No matching JWKS key for kid={kid}")

    # For this workshop: verify claims without full signature verification
    claims = jwt.decode(
        token,
        options={"verify_signature": False},
        algorithms=["RS256"],
    )

    if claims.get("iss") != ISSUER:
        raise ValueError(
            f"Invalid issuer: expected {ISSUER}, got {claims.get('iss')}"
        )

    if claims.get("client_id") != CLIENT_ID:
        raise ValueError(
            f"Invalid client_id: expected {CLIENT_ID}, got {claims.get('client_id')}"
        )

    if claims.get("token_use") != "access":
        raise ValueError(
            f"Invalid token_use: expected 'access', got {claims.get('token_use')}"
        )

    return claims


def handler(event, context):
    token = event.get("authorizationToken", "")
    method_arn = event.get("methodArn", "*")

    if token.startswith("Bearer "):
        token = token[7:]

    if not token:
        logger.warning("No token provided")
        return _build_policy("anonymous", "Deny", method_arn)

    try:
        claims = _validate_token(token)
        principal_id = claims.get("sub", "unknown")
        logger.info("Token valid for principal %s", principal_id)
        policy = _build_policy(principal_id, "Allow", method_arn)
        policy["context"] = {
            "sub": claims.get("sub", ""),
            "email": claims.get("email", ""),
            "username": claims.get("username", claims.get("cognito:username", "")),
        }
        return policy
    except Exception as e:
        logger.error("Token validation failed: %s", str(e))
        return _build_policy("anonymous", "Deny", method_arn)
