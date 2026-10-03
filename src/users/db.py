import os
import uuid

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.exceptions import ClientError

_dynamodb = boto3.resource("dynamodb")


def _table():
    return _dynamodb.Table(os.environ["USERS_TABLE_NAME"])


class UserNotFoundError(Exception):
    pass


def scan_users() -> list:
    return _table().scan()["Items"]


def create_user(first_name: str, last_name: str, email: str) -> dict:
    user = {
        "userid": str(uuid.uuid4()),
        "first_name": first_name,
        "last_name": last_name,
        "email": email,
    }
    _table().put_item(
        Item=user,
        ConditionExpression=Attr("userid").not_exists(),
    )
    return user


def get_user(userid: str):
    return _table().get_item(Key={"userid": userid}).get("Item")


def update_user(userid: str, updates: dict) -> dict:
    set_parts = [f"{k} = :{k}" for k in updates]
    expr_vals = {f":{k}": v for k, v in updates.items()}
    try:
        result = _table().update_item(
            Key={"userid": userid},
            UpdateExpression="SET " + ", ".join(set_parts),
            ExpressionAttributeValues=expr_vals,
            ConditionExpression=Attr("userid").exists(),
            ReturnValues="ALL_NEW",
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise UserNotFoundError(userid) from exc
        raise
    return result["Attributes"]


def delete_user(userid: str) -> None:
    try:
        _table().delete_item(
            Key={"userid": userid},
            ConditionExpression=Attr("userid").exists(),
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise UserNotFoundError(userid) from exc
        raise
