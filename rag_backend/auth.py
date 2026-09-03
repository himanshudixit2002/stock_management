"""
Request authentication.

The service previously trusted the `x-company-id` header on its own. The client
was already attaching a Firebase ID token — it was simply never verified — so a
request carrying nothing but a company id was answered in full. Every Firestore
read here is scoped by that id, which made any tenant's inventory readable, and
the write endpoints reachable, by anyone who knew or guessed one.

Membership is checked against `companies/{cid}/members/{uid}` rather than
`users/{uid}.companyId`. That collection is the same server-side record the
Firestore security rules use (`hasMemberDoc()`), and it is written by trusted
paths only; `companyMemberships` on the user document is client-written and a
user may legitimately belong to several workspaces.

Membership alone is not enough to *write*. Everything here goes through the
Firebase Admin SDK, which bypasses `firestore.rules` entirely, so a route that
only proved membership handed every member the write powers the rules spend
hundreds of lines withholding: a viewer denied `canStockIn` in the app could ask
the assistant to add 500 units and have it succeed. `require_permission` mirrors
the rules' own `hasPermission()` so the two agree on who may change what.
"""

import os
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from typing import Any, Deque, Dict, Optional, Tuple

from fastapi import Header, HTTPException

# Set OFFLINE_MODE=1 (local development only) to bypass verification. Never set
# this on Cloud Run — it disables the check this module exists to perform.
_OFFLINE = os.getenv("OFFLINE_MODE") == "1"

_MEMBER_CACHE_TTL_SECONDS = 300
_member_cache: Dict[str, float] = {}

# Deliberately far shorter than the membership TTL. A stale *membership* only
# delays a removal; a stale *permission* map would keep granting a write power
# that was just revoked, so this is the one thing worth re-reading often.
_PERMISSION_CACHE_TTL_SECONDS = 30
_permission_cache: Dict[str, Tuple[float, Dict[str, bool]]] = {}


def _bearer(authorization: Optional[str]) -> str:
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail={
                "error": "missing_token",
                "message": "This endpoint requires a signed-in user.",
            },
        )
    parts = authorization.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1].strip():
        raise HTTPException(
            status_code=401,
            detail={"error": "malformed_token", "message": "Malformed Authorization header."},
        )
    return parts[1].strip()


def _verify(token: str) -> str:
    """Returns the uid, or raises 401. Never leaks the verifier's message."""
    try:
        from firebase_admin import auth as fb_auth
        import inventory_db  # noqa: F401  — ensures initialize_app has run
        decoded = fb_auth.verify_id_token(token)
    except Exception:
        raise HTTPException(
            status_code=401,
            detail={"error": "invalid_token", "message": "Sign in again and retry."},
        )
    uid = decoded.get("uid") or decoded.get("user_id")
    if not uid:
        raise HTTPException(
            status_code=401,
            detail={"error": "invalid_token", "message": "Sign in again and retry."},
        )
    return uid


def _is_member(uid: str, company_id: str) -> bool:
    """Whether `companies/{company_id}/members/{uid}` exists.

    Cached briefly: this runs on every request, and membership changes rarely.
    A removed member keeps access for at most the TTL.
    """
    key = f"{company_id}/{uid}"
    now = time.time()
    hit = _member_cache.get(key)
    if hit is not None and now - hit < _MEMBER_CACHE_TTL_SECONDS:
        return True

    try:
        from inventory_db import db_firestore
    except Exception:
        db_firestore = None
    if db_firestore is None:
        # No Firestore means membership cannot be established. Failing closed is
        # the only safe answer — failing open is the bug this file fixes.
        return False

    try:
        snap = (
            db_firestore.collection("companies")
            .document(company_id)
            .collection("members")
            .document(uid)
            .get()
        )
    except Exception:
        return False

    if snap.exists:
        _member_cache[key] = now
        return True
    return False


def _doc(*path: str) -> Optional[Dict[str, Any]]:
    """Reads one Firestore document, or None if it is missing/unreachable."""
    try:
        from inventory_db import db_firestore
    except Exception:
        return None
    if db_firestore is None:
        return None
    try:
        ref = db_firestore.collection(path[0]).document(path[1])
        for i in range(2, len(path), 2):
            ref = ref.collection(path[i]).document(path[i + 1])
        snap = ref.get()
    except Exception:
        return None
    return snap.to_dict() if snap.exists else None


def _permissions_for(uid: str, company_id: str) -> Dict[str, bool]:
    """The caller's effective permission map, mirroring rules' hasPermission().

    Resolution order matches `firestore.rules` exactly, because the two must
    agree — anywhere they diverge is a way to do through the assistant something
    the app itself forbids:

      1. role 'admin'/'owner' short-circuits to everything;
      2. otherwise the role document at companies/{cid}/roles/{roleId};
      3. plus any per-user overrides on the user document.

    An unreadable user document yields no permissions rather than raising, so a
    Firestore hiccup denies writes instead of allowing them.
    """
    key = f"{company_id}/{uid}"
    now = time.time()
    hit = _permission_cache.get(key)
    if hit is not None and now - hit[0] < _PERMISSION_CACHE_TTL_SECONDS:
        return hit[1]

    user = _doc("users", uid) or {}
    resolved: Dict[str, bool] = {}

    role = str(user.get("role") or "")
    if role in ("admin", "owner"):
        resolved["*"] = True
    else:
        role_id = str(user.get("roleId") or "")
        if role_id:
            role_doc = _doc("companies", company_id, "roles", role_id) or {}
            granted = role_doc.get("permissions")
            if isinstance(granted, dict):
                for k, v in granted.items():
                    if v is True:
                        resolved[str(k)] = True
        overrides = user.get("permissions")
        if isinstance(overrides, dict):
            for k, v in overrides.items():
                if v is True:
                    resolved[str(k)] = True

    _permission_cache[key] = (now, resolved)
    return resolved


@dataclass(frozen=True)
class Principal:
    """Who is calling, and which workspace they proved access to."""

    uid: str
    company_id: str

    def has(self, permission: str) -> bool:
        if _OFFLINE:
            return True
        granted = _permissions_for(self.uid, self.company_id)
        return granted.get("*", False) or granted.get(permission, False)

    def granted(self) -> set:
        """The permission keys this caller holds, for passing into the agent.

        `'*'` means admin/owner. Offline development returns `'*'` so the local
        loop is not blocked by a check it cannot perform.
        """
        if _OFFLINE:
            return {"*"}
        return set(_permissions_for(self.uid, self.company_id).keys())


async def verified_principal(
    authorization: Optional[str] = Header(None),
    x_company_id: Optional[str] = Header(None, alias="x-company-id"),
) -> Principal:
    """FastAPI dependency: the verified caller and the workspace they may act on."""
    company_id = (x_company_id or "").strip()
    if not company_id or company_id == "default":
        raise HTTPException(
            status_code=400,
            detail={
                "error": "company_id_required",
                "message": "No workspace was identified for this request.",
            },
        )

    if _OFFLINE:
        return Principal(uid="offline", company_id=company_id)

    uid = _verify(_bearer(authorization))
    if not _is_member(uid, company_id):
        # 403, not 404: the caller is authenticated, just not a member. The
        # message deliberately does not confirm whether the workspace exists.
        raise HTTPException(
            status_code=403,
            detail={
                "error": "not_a_member",
                "message": "You do not have access to this workspace.",
            },
        )
    return Principal(uid=uid, company_id=company_id)


async def verified_company_id(
    authorization: Optional[str] = Header(None),
    x_company_id: Optional[str] = Header(None, alias="x-company-id"),
) -> str:
    """FastAPI dependency: the company id this request is allowed to act on.

    Read-only routes only. Anything that writes should depend on
    [require_permission] instead, so the permission the app enforces client-side
    is enforced here too.
    """
    principal = await verified_principal(authorization, x_company_id)
    return principal.company_id


def require_permission(permission: str):
    """Dependency factory: membership *and* [permission], returning the company id.

    Use on every mutating route. `permission` is one of the same
    `AppPermissions` keys the Flutter client uses (e.g. 'canStockIn'), so the
    grant being checked is literally the one an admin toggled in the app.
    """

    # Named for what it returns and what it additionally proves. The name is
    # load-bearing: test_auth walks the routes and identifies an authenticated
    # one by the dependency's name, so an opaque `_dependency` would read as an
    # open route.
    async def verified_company_id_with_permission(
        authorization: Optional[str] = Header(None),
        x_company_id: Optional[str] = Header(None, alias="x-company-id"),
    ) -> str:
        principal = await verified_principal(authorization, x_company_id)
        if not principal.has(permission):
            raise HTTPException(
                status_code=403,
                detail={
                    "error": "permission_denied",
                    "permission": permission,
                    "message": (
                        "Your role does not allow this change. Ask an admin for "
                        "the required permission."
                    ),
                },
            )
        return principal.company_id

    return verified_company_id_with_permission


# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------

_RATE_LIMIT_WINDOW_SECONDS = 60
_RATE_LIMIT_MAX_REQUESTS = int(os.getenv("RATE_LIMIT_PER_MINUTE", "30"))
_hits: Dict[str, Deque[float]] = defaultdict(deque)


def rate_limit(company_id: str) -> None:
    """Rejects a company that exceeds the per-minute budget.

    In-memory, so the budget is **per Cloud Run instance** — as the service
    scales out the effective ceiling rises. This is a cost guard against a
    runaway loop, not a quota; real enforcement needs shared state.
    """
    now = time.time()
    window = _hits[company_id]
    cutoff = now - _RATE_LIMIT_WINDOW_SECONDS
    while window and window[0] < cutoff:
        window.popleft()
    if len(window) >= _RATE_LIMIT_MAX_REQUESTS:
        raise HTTPException(
            status_code=429,
            detail={
                "error": "rate_limited",
                "message": "Too many requests. Wait a moment and try again.",
            },
        )
    window.append(now)


async def verified_company_id_rate_limited(
    authorization: Optional[str] = Header(None),
    x_company_id: Optional[str] = Header(None, alias="x-company-id"),
) -> str:
    """[verified_company_id] plus the per-company budget, for model-calling routes."""
    company_id = await verified_company_id(authorization, x_company_id)
    rate_limit(company_id)
    return company_id


async def verified_principal_rate_limited(
    authorization: Optional[str] = Header(None),
    x_company_id: Optional[str] = Header(None, alias="x-company-id"),
) -> Principal:
    """[verified_principal] plus the per-company budget.

    For the chat routes, which need the caller's identity as well as the
    workspace: the agent can execute writes, and it has to know what this
    particular caller is allowed to change.
    """
    principal = await verified_principal(authorization, x_company_id)
    rate_limit(principal.company_id)
    return principal
