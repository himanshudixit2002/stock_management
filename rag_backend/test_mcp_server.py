"""Tests for the MCP surface.

The MCP server is a third front door onto the same inventory, and a third front
door is a third chance to get tenant isolation and permissions wrong. Two
things are pinned here.

*It quotes the same numbers as everything else.* Valuation and low-stock counts
are compared against the fact layer directly, so the MCP tools cannot quietly
grow their own arithmetic.

*It is not a way around a permission.* Writes are off by default, refused
without the grant, and refused again when the product name is only a near miss.

Run:  venv/bin/python test_mcp_server.py
"""

import os
import sys

os.environ["OFFLINE_MODE"] = "1"
os.environ["MCP_COMPANY_ID"] = "mcp_test"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from evals import catalogs
from facts import fact_store
from inventory_db import db_instance

CID = "mcp_test"
_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


def seed():
    db_instance.replace_user_inventory(catalogs.catalog("default"), company_id=CID)
    fact_store.bump(CID)
    return fact_store.get(CID, force=True)


import mcp_server as mcp  # noqa: E402

facts = seed()
truth = catalogs.truth("default")

print("\nthe MCP tools quote the fact layer, not their own arithmetic")
summary = mcp.inventory_summary()
check("total_products", summary["total_products"], truth["total_products"])
check("low_stock_count", summary["low_stock_count"], truth["low_stock_count"])
check("out_of_stock_count", summary["out_of_stock_count"], truth["out_of_stock_count"])

val = mcp.valuation()
check("retail_value", val["retail_value"], truth["retail_value"])
check("cost_value", val["cost_value"], truth["cost_value"])

low = mcp.low_stock()
check("low_stock rows", len(low["products"]), truth["low_stock_count"])
check(
    "low_stock names are the real ones",
    sorted(p["name"] for p in low["products"]),
    sorted(truth["low_stock_names"]),
)

print("\nno row refers to a product that does not exist")
known = {p.barcode for p in facts.products}
for tool_name, payload in (
    ("low_stock", mcp.low_stock()),
    ("reorder_plan", mcp.reorder_plan()),
    ("list_products", mcp.list_products()),
):
    ghosts = [r["name"] for r in payload["products"] if r["barcode"] not in known]
    check(f"{tool_name} has no invented rows", ghosts, [])

print("\nmissing demand history is admitted, not filled in")
check("history flagged unreliable", summary["demand_figures_reliable"], False)
check("a note explains why", "note" in summary, True)
check("dead_stock declines to guess", mcp.dead_stock()["available"], False)

print("\na product that does not exist is not substituted for one that does")
miss = mcp.find_product("Artisanal Sourdough")
check("found is False", miss["found"], False)
check("catalog size is reported", miss["catalog_size"], truth["total_products"])
hit = mcp.find_product("Fresh Apples (kg)")
check("an exact name resolves", hit["product"]["name"], "Fresh Apples (kg)")

print("\nwrites are off by default")
mcp.ALLOW_WRITES = False
r = mcp.adjust_stock("Fresh Apples (kg)", 10)
check("refused", r["error"], "writes_disabled")
check("stock untouched", fact_store.get(CID, force=True).by_barcode("89010001").quantity, 15)

print("\nwrites enabled still need the grant")
mcp.ALLOW_WRITES = True
mcp.PERMISSIONS = set()
r = mcp.adjust_stock("Fresh Apples (kg)", 10)
check("refused", r["error"], "permission_denied")
check("stock untouched", fact_store.get(CID, force=True).by_barcode("89010001").quantity, 15)

print("\nan unreadable grant set fails closed, like the agent")
mcp.PERMISSIONS = set()   # falsy -> passed to may_run_tool as None
check("may_run_tool refuses on None", mcp.nodes.may_run_tool("update_stock", None), False)

print("\na near-miss name is refused rather than guessed at")
mcp.PERMISSIONS = {"canAdjustStock"}
r = mcp.adjust_stock("apples", 10)
check("refused as ambiguous", r["error"], "ambiguous_product")
check("stock untouched", fact_store.get(CID, force=True).by_barcode("89010001").quantity, 15)

r = mcp.adjust_stock("Totally Made Up Product", 10)
check("an invented product is refused", r["error"], "product_not_found")

print("\nthe control: an exact name with the grant does write")
r = mcp.adjust_stock("Fresh Apples (kg)", 50, reason="test")
check("succeeded", r.get("success"), True)
check("stock moved to 65", fact_store.get(CID, force=True).by_barcode("89010001").quantity, 65)

print("\nthe workspace is never guessed")
_saved = mcp.COMPANY_ID
try:
    mcp.COMPANY_ID = ""
    raised = False
    try:
        mcp._require_company()
    except ValueError:
        raised = True
    check("an unset MCP_COMPANY_ID raises rather than defaulting", raised, True)
finally:
    mcp.COMPANY_ID = _saved

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All MCP server tests passed.")
