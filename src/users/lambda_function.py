import json
import logging
import os
import uuid

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")


def _table():
    return dynamodb.Table(os.environ["USERS_TABLE_NAME"])


# ── CORS / response helpers ───────────────────────────────────────────────────

HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
}


def _response(status_code: int, body) -> dict:
    return {
        "statusCode": status_code,
        "headers": HEADERS,
        "body": json.dumps(body),
    }


def _error(status_code: int, message: str) -> dict:
    return _response(status_code, {"error": message})


# ── DynamoDB operations ───────────────────────────────────────────────────────

def _scan_users() -> list:
    logger.info("Scanning all users")
    return _table().scan()["Items"]


def _create_user(first_name: str, last_name: str, email: str) -> dict:
    user = {
        "userid": str(uuid.uuid4()),
        "first_name": first_name,
        "last_name": last_name,
        "email": email,
    }
    logger.info("Creating user with userid=%s", user["userid"])
    _table().put_item(
        Item=user,
        ConditionExpression=Attr("userid").not_exists(),
    )
    return user


def _get_user(userid: str):
    logger.info("Fetching user userid=%s", userid)
    return _table().get_item(Key={"userid": userid}).get("Item")


def _update_user(userid: str, updates: dict) -> dict:
    logger.info("Updating user userid=%s fields=%s", userid, list(updates.keys()))
    set_parts = [f"{k} = :{k}" for k in updates]
    expr_vals = {f":{k}": v for k, v in updates.items()}
    result = _table().update_item(
        Key={"userid": userid},
        UpdateExpression="SET " + ", ".join(set_parts),
        ExpressionAttributeValues=expr_vals,
        ConditionExpression=Attr("userid").exists(),
        ReturnValues="ALL_NEW",
    )
    return result["Attributes"]


def _delete_user(userid: str) -> None:
    logger.info("Deleting user userid=%s", userid)
    _table().delete_item(
        Key={"userid": userid},
        ConditionExpression=Attr("userid").exists(),
    )


# ── Route handlers ────────────────────────────────────────────────────────────

def _handle_list_users(_event: dict) -> dict:
    users = _scan_users()
    return _response(200, users)


def _handle_create_user(event: dict) -> dict:
    body = json.loads(event.get("body") or "{}")
    for field in ("first_name", "last_name", "email"):
        if not body.get(field):
            return _error(400, f"Missing required field: {field}")
    user = _create_user(body["first_name"], body["last_name"], body["email"])
    return _response(201, user)


def _handle_get_user(event: dict) -> dict:
    userid = event["pathParameters"]["userid"]
    user = _get_user(userid)
    if user is None:
        return _error(404, f"User '{userid}' not found")
    return _response(200, user)


def _handle_update_user(event: dict) -> dict:
    userid = event["pathParameters"]["userid"]
    body = json.loads(event.get("body") or "{}")
    updates = {k: body[k] for k in ("first_name", "last_name", "email") if k in body}
    if not updates:
        return _error(400, "Request body must include at least one of: first_name, last_name, email")
    try:
        user = _update_user(userid, updates)
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _error(404, f"User '{userid}' not found")
        raise
    return _response(200, user)


def _handle_delete_user(event: dict) -> dict:
    userid = event["pathParameters"]["userid"]
    try:
        _delete_user(userid)
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _error(404, f"User '{userid}' not found")
        raise
    return _response(200, {"message": f"User '{userid}' deleted successfully"})


# ── Dispatch ──────────────────────────────────────────────────────────────────

_ROUTES = {
    ("GET",    "/users"):           _handle_list_users,
    ("POST",   "/users"):           _handle_create_user,
    ("GET",    "/users/{userid}"):  _handle_get_user,
    ("PUT",    "/users/{userid}"):  _handle_update_user,
    ("DELETE", "/users/{userid}"): _handle_delete_user,
}


def lambda_handler(event: dict, context) -> dict:
    method = event.get("httpMethod", "")
    resource = event.get("resource", "")
    logger.info("Request: %s %s", method, resource)

    # Handle CORS preflight
    if method == "OPTIONS":
        return _response(200, {})

    route_fn = _ROUTES.get((method, resource))
    if route_fn is None:
        return _error(404, f"Route not found: {method} {resource}")

    try:
        return route_fn(event)
    except ClientError:
        logger.exception("DynamoDB error")
        return _error(500, "Internal server error")
    except Exception:
        logger.exception("Unexpected error")
        return _error(500, "Internal server error")
