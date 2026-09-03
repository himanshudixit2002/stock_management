"""
Auth tests for the API surface.

The bug these pin: the service used to answer any request that carried an
`x-company-id` header, with no token check at all, so any tenant's inventory was
readable by anyone who knew or guessed a company id.

Run: ./venv/bin/python test_auth.py
"""

import inspect
import os
import sys

os.environ.pop("OFFLINE_MODE", None)

from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

import auth
import main

client = TestClient(main.app, raise_server_exceptions=False)

FAILURES = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name} {detail}")
        FAILURES.append(name)


print("\nevery route except /health requires a verified company")
open_routes = []
for r in main.app.routes:
    if isinstance(r, APIRoute):
        sig = inspect.signature(r.endpoint)
        authed = any("verified_company_id" in str(p.default) for p in sig.parameters.values())
        if not authed:
            open_routes.append(r.path)
check("only /health is unauthenticated", open_routes == ["/health"], open_routes)

print("\nhealth stays reachable, and says nothing about any tenant")
r = client.get("/health")
check("/health is 200 without credentials", r.status_code == 200, r.status_code)
body = r.json()
check(
    "/health leaks no tenant data",
    "inventory" not in body and "fingerprint" not in body,
    list(body),
)

print("\nno credentials is rejected")
r = client.post("/api/chat", json={"question": "hi"}, headers={"x-company-id": "acme"})
check("POST /api/chat without a token is 401", r.status_code == 401, r.status_code)
r = client.get("/api/agent/autopilot", headers={"x-company-id": "acme"})
check("GET /api/agent/autopilot without a token is 401", r.status_code == 401, r.status_code)

print("\nthe previously unscoped routes are closed")
r = client.get("/api/swarm/logs")
check("/api/swarm/logs is no longer open", r.status_code in (400, 401), r.status_code)
r = client.post("/api/swarm/approve_po", json={"po_id": "x"})
check("/api/swarm/approve_po is no longer open", r.status_code in (400, 401, 422), r.status_code)
r = client.get("/api/cache/stats")
check("/api/cache/stats is no longer open", r.status_code in (400, 401), r.status_code)

print("\na malformed Authorization header is rejected")
for header in ("", "Bearer", "Token abc", "Bearer   "):
    r = client.post(
        "/api/chat",
        json={"question": "hi"},
        headers={"x-company-id": "acme", "Authorization": header},
    )
    check(f"Authorization={header!r} is 401", r.status_code == 401, r.status_code)

print("\na missing workspace is a 400, before any token work")
r = client.post("/api/chat", json={"question": "hi"})
check("no x-company-id is 400", r.status_code == 400, r.status_code)

print("\nmembership decides access")
_real_verify, _real_member = auth._verify, auth._is_member
try:
    auth._verify = lambda token: "user-1"
    auth._is_member = lambda uid, cid: cid == "acme"
    auth._member_cache.clear()

    r = client.get("/api/cache/stats", headers={"x-company-id": "other", "Authorization": "Bearer t"})
    check("a non-member gets 403", r.status_code == 403, r.status_code)

    r = client.get("/api/cache/stats", headers={"x-company-id": "acme", "Authorization": "Bearer t"})
    check("a member is allowed through", r.status_code == 200, r.status_code)
finally:
    auth._verify, auth._is_member = _real_verify, _real_member
    auth._member_cache.clear()

print("\nmembership fails closed when Firestore is unavailable")
check(
    "no Firestore client means not a member",
    auth._is_member("nobody", "acme") is False,
)

print("\nthe rate limiter trips")
auth._hits.clear()
limit = auth._RATE_LIMIT_MAX_REQUESTS
try:
    for _ in range(limit):
        auth.rate_limit("acme")
    tripped = False
    try:
        auth.rate_limit("acme")
    except Exception as e:
        tripped = getattr(e, "status_code", None) == 429
    check(f"request {limit + 1} in a minute is 429", tripped)
    # A different company has its own budget.
    auth.rate_limit("other")
    check("the budget is per company", True)
finally:
    auth._hits.clear()

print("\nCORS is not wide open")
from fastapi.middleware.cors import CORSMiddleware
origins = []
for m in main.app.user_middleware:
    if m.cls is CORSMiddleware:
        origins = m.kwargs.get("allow_origins", [])
check("allow_origins is not ['*']", "*" not in origins, origins)

print()
if FAILURES:
    print(f"{len(FAILURES)} failing: {FAILURES}")
    sys.exit(1)
print("all auth checks passed")
