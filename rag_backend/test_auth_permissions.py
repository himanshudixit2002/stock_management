"""Permission gating for the assistant's write path.

Everything this service writes goes through the Firebase Admin SDK, which
bypasses firestore.rules entirely. These tests pin the two halves of the guard
that replaces the rules here:

  * `_permissions_for` resolves a caller's grants the same way the rules'
    `hasPermission()` does (admin/owner short-circuit, then the role document,
    then per-user overrides);
  * `may_run_tool` refuses a write tool the caller has no grant for, and fails
    closed when the grants could not be read at all.

Run with:  rag_backend/venv/bin/python -m pytest rag_backend/test_auth_permissions.py -q
"""

import auth
import nodes


def _reset_cache():
    auth._permission_cache.clear()


def _with_docs(monkeypatch, docs):
    """Stubs auth._doc so no Firestore is needed."""
    def fake_doc(*path):
        return docs.get("/".join(path))

    monkeypatch.setattr(auth, "_doc", fake_doc)
    _reset_cache()


def test_admin_role_short_circuits_to_everything(monkeypatch):
    _with_docs(monkeypatch, {"users/u1": {"role": "admin", "roleId": "admin"}})
    assert auth.Principal(uid="u1", company_id="c1").has("canStockIn")
    assert auth.Principal(uid="u1", company_id="c1").has("canCreatePurchaseOrders")


def test_owner_role_short_circuits_to_everything(monkeypatch):
    _with_docs(monkeypatch, {"users/u1": {"role": "owner", "roleId": "owner"}})
    assert auth.Principal(uid="u1", company_id="c1").has("canAdjustStock")


def test_viewer_is_denied_writes(monkeypatch):
    _with_docs(
        monkeypatch,
        {
            "users/u2": {"role": "viewer", "roleId": "viewer"},
            "companies/c1/roles/viewer": {
                "permissions": {"canViewProducts": True, "canStockIn": False}
            },
        },
    )
    principal = auth.Principal(uid="u2", company_id="c1")
    assert principal.has("canViewProducts")
    assert not principal.has("canStockIn")
    assert not principal.has("canAdjustStock")


def test_role_document_grants_are_honoured(monkeypatch):
    _with_docs(
        monkeypatch,
        {
            "users/u3": {"role": "staff", "roleId": "custom"},
            "companies/c1/roles/custom": {"permissions": {"canStockIn": True}},
        },
    )
    principal = auth.Principal(uid="u3", company_id="c1")
    assert principal.has("canStockIn")
    assert not principal.has("canCreatePurchaseOrders")


def test_per_user_override_grants(monkeypatch):
    _with_docs(
        monkeypatch,
        {
            "users/u4": {
                "role": "staff",
                "roleId": "viewer",
                "permissions": {"canAdjustStock": True},
            },
            "companies/c1/roles/viewer": {"permissions": {}},
        },
    )
    assert auth.Principal(uid="u4", company_id="c1").has("canAdjustStock")


def test_missing_user_document_grants_nothing(monkeypatch):
    _with_docs(monkeypatch, {})
    principal = auth.Principal(uid="ghost", company_id="c1")
    assert not principal.has("canStockIn")
    assert principal.granted() == set()


def test_permissions_are_scoped_per_company(monkeypatch):
    # The same uid, admin in one workspace and a viewer in another. Caching must
    # not let the first answer stand in for the second.
    _with_docs(
        monkeypatch,
        {
            "users/u5": {"role": "staff", "roleId": "r"},
            "companies/c1/roles/r": {"permissions": {"canStockIn": True}},
            "companies/c2/roles/r": {"permissions": {}},
        },
    )
    assert auth.Principal(uid="u5", company_id="c1").has("canStockIn")
    assert not auth.Principal(uid="u5", company_id="c2").has("canStockIn")


# --- the tool-level guard --------------------------------------------------


def test_read_tools_need_no_permission():
    assert nodes.may_run_tool("get_product", set())
    assert nodes.may_run_tool("inventory_summary", None)


def test_write_tools_require_their_grant():
    assert not nodes.may_run_tool("update_stock", {"canViewProducts"})
    assert nodes.may_run_tool("update_stock", {"canAdjustStock"})
    assert nodes.may_run_tool("create_purchase_order", {"canCreatePurchaseOrders"})
    assert not nodes.may_run_tool("create_purchase_order", {"canAdjustStock"})


def test_admin_wildcard_runs_any_tool():
    for tool in nodes.WRITE_TOOL_PERMISSIONS:
        assert nodes.may_run_tool(tool, {"*"})


def test_unknown_permissions_fail_closed():
    # None means "could not be established" — writes must be refused, not
    # allowed, so a Firestore hiccup cannot open the write path.
    for tool in nodes.WRITE_TOOL_PERMISSIONS:
        assert not nodes.may_run_tool(tool, None)


def test_every_write_tool_has_a_permission():
    # A new write tool with no mapping would silently need no permission.
    assert set(nodes.WRITE_TOOL_NAMES) == set(nodes.WRITE_TOOL_PERMISSIONS)
