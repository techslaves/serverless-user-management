import json
import importlib
import pytest

import lambda_function


def _event(method, resource, path_params=None, body=None):
    return {
        "httpMethod": method,
        "resource": resource,
        "pathParameters": path_params,
        "body": json.dumps(body) if body else None,
    }


def _create_payload():
    return {"first_name": "Jane", "last_name": "Doe", "email": "jane@example.com"}


def _create(users_table):
    resp = lambda_function.lambda_handler(_event("POST", "/users", body=_create_payload()), {})
    return json.loads(resp["body"])


# ── GET /users ────────────────────────────────────────────────────────────────

def test_list_users_empty(users_table):
    resp = lambda_function.lambda_handler(_event("GET", "/users"), {})
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"]) == []


def test_list_users_returns_items(users_table):
    _create(users_table)
    resp = lambda_function.lambda_handler(_event("GET", "/users"), {})
    assert len(json.loads(resp["body"])) == 1


# ── POST /users ───────────────────────────────────────────────────────────────

def test_create_user_returns_201_with_userid(users_table):
    resp = lambda_function.lambda_handler(_event("POST", "/users", body=_create_payload()), {})
    assert resp["statusCode"] == 201
    body = json.loads(resp["body"])
    assert "userid" in body
    assert body["email"] == "jane@example.com"


def test_create_user_missing_field_returns_400(users_table):
    resp = lambda_function.lambda_handler(
        _event("POST", "/users", body={"first_name": "Jane"}), {}
    )
    assert resp["statusCode"] == 400
    assert "last_name" in json.loads(resp["body"])["error"]


# ── GET /users/{userid} ───────────────────────────────────────────────────────

def test_get_user_found(users_table):
    created = _create(users_table)
    resp = lambda_function.lambda_handler(
        _event("GET", "/users/{userid}", path_params={"userid": created["userid"]}), {}
    )
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"])["userid"] == created["userid"]


def test_get_user_not_found_returns_404(users_table):
    resp = lambda_function.lambda_handler(
        _event("GET", "/users/{userid}", path_params={"userid": "nonexistent"}), {}
    )
    assert resp["statusCode"] == 404


# ── PUT /users/{userid} ───────────────────────────────────────────────────────

def test_update_user(users_table):
    userid = _create(users_table)["userid"]
    resp = lambda_function.lambda_handler(
        _event("PUT", "/users/{userid}", path_params={"userid": userid},
               body={"email": "new@example.com"}), {}
    )
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"])["email"] == "new@example.com"


def test_update_nonexistent_user_returns_404(users_table):
    resp = lambda_function.lambda_handler(
        _event("PUT", "/users/{userid}", path_params={"userid": "ghost"},
               body={"email": "x@x.com"}), {}
    )
    assert resp["statusCode"] == 404


# ── DELETE /users/{userid} ────────────────────────────────────────────────────

def test_delete_user(users_table):
    userid = _create(users_table)["userid"]
    resp = lambda_function.lambda_handler(
        _event("DELETE", "/users/{userid}", path_params={"userid": userid}), {}
    )
    assert resp["statusCode"] == 200


def test_delete_nonexistent_returns_404(users_table):
    resp = lambda_function.lambda_handler(
        _event("DELETE", "/users/{userid}", path_params={"userid": "ghost"}), {}
    )
    assert resp["statusCode"] == 404
