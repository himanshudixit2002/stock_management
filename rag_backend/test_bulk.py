"""Bulk (multi-product) requests, end to end and without an LLM.

The bug these cover: *"add 10 pieces for all low stock"* produced a **new
product** called "pieces". Nothing in the pipeline could express "this
instruction is about a set of products", so the sentence was handed to the
single-product resolver, reduced to the token "low", matched nothing, and fell
through to product creation.
"""

import asyncio
import sys

sys.path.insert(0, ".")

import testkit  # sets OFFLINE_MODE

import bulk
from facts import fact_store
from nodes import execution_agent_node, retrieve_node, router_node
from pending import pending_actions

CID = testkit.TEST_COMPANY
SID = "bulk_session"

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


def contains(label, haystack, needle):
    ok = needle.lower() in (haystack or "").lower()
    if not ok:
        _failures.append(f"{label}: {needle!r} missing from output")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


def excludes(label, haystack, needle):
    ok = needle.lower() not in (haystack or "").lower()
    if not ok:
        _failures.append(f"{label}: {needle!r} should not appear in output")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


def run(question, facts, permissions=frozenset({"*"})):
    """Route → retrieve → execute, the way the graph does."""
    state = {
        "question": question,
        "company_id": CID,
        "session_id": SID,
        "facts": facts,
        "business_type": "retail_store",
        "permissions": set(permissions),
        "history": [],
    }
    state = asyncio.run(router_node(state))
    state = asyncio.run(retrieve_node(state))
    if state.get("intent") == "EXECUTION":
        state = asyncio.run(execution_agent_node(state))
    return state


# ---------------------------------------------------------------------------

print("\n== The reported bug: a bulk request must not create a product ==")
pending_actions.clear(CID, SID)
facts = testkit.seed()
# Fresh Apples (15/50) and Organic Whole Milk (8/30) are below threshold.
state = run("add 10 pieces for all low stock", facts)

check("routed to execution", state.get("intent"), "EXECUTION")
check("routed by the bulk rule", state.get("route_source"), "bulk")
check("previewed as a bulk change", state.get("response_kind"), "bulk_preview")
check("no model call was needed", state.get("llm_calls"), 0)
action = state.get("pending_action") or {}
check("pending action is bulk", action.get("tool"), "__bulk__")
check("it is a stock change", action.get("inner_tool"), "update_stock")
check("over the low-stock selector", action.get("selector"), "low_stock")
check("covering both low products", action.get("count"), 2)
contains("names a real product", state.get("generation"), "Fresh Apples")
contains("names the other one", state.get("generation"), "Organic Whole Milk")
contains("shows the projected stock", state.get("generation"), "25")
excludes("nothing was created", state.get("generation"), "new product")
excludes("no invented product name", state.get("generation"), "pieces |")


print("\n== Confirming applies it to every matched product ==")
state = run("confirm", facts)
check("executed", state.get("response_kind"), "executed")
record = (state.get("executed_actions") or [{}])[0]
check("recorded as a bulk stock change", record.get("tool"), "bulk_update_stock")
check("two products written", record.get("result", {}).get("applied"), 2)
check("none failed", record.get("result", {}).get("failed"), 0)

after = fact_store.get(CID, force=True)
check("apples went 15 -> 25", after.by_barcode("89010001").quantity, 25)
check("milk went 8 -> 18", after.by_barcode("89010004").quantity, 18)
check("untouched product unchanged", after.by_barcode("89010002").quantity, 100)
check("pending cleared", pending_actions.get(CID, SID), None)


print("\n== Nothing qualifying is an answer, not a product-creation prompt ==")
pending_actions.clear(CID, SID)
facts = testkit.seed([
    {"id": "p1", "barcode": "111", "name": "Widget", "stock": 500,
     "min_threshold": 10, "category": "General", "cost_price": 1.0,
     "selling_price": 2.0},
])
state = run("add 10 units to every low stock item", facts)
check("no pending write", state.get("pending_action"), None)
check("plain prose", state.get("response_kind"), "prose")
contains("says nothing is low", state.get("generation"), "nothing is running low")
excludes("does not ask for a location", state.get("generation"), "where should")


print("\n== Top up to each product's own threshold ==")
pending_actions.clear(CID, SID)
facts = testkit.seed()
state = run("restock all low stock items back to their minimum", facts)
action = state.get("pending_action") or {}
check("per-product quantity", action.get("mode"), "to_min")
targets = {t["name"]: t["change"] for t in action.get("targets", [])}
check("apples need 35", targets.get("Fresh Apples (kg)"), 35)
check("milk needs 22", targets.get("Organic Whole Milk 1L"), 22)

state = run("yes", facts)
after = fact_store.get(CID, force=True)
check("apples now at threshold", after.by_barcode("89010001").quantity, 50)
check("milk now at threshold", after.by_barcode("89010004").quantity, 30)


print("\n== Deducting in bulk is still a stock change, and still gated ==")
pending_actions.clear(CID, SID)
facts = testkit.seed()
state = run("remove 5 units from all products", facts)
action = state.get("pending_action") or {}
check("selector is the whole catalog", action.get("selector"), "all")
check("negative delta", (action.get("args") or {}).get("qty_change"), -5)
check("covers every product", action.get("count"), 4)

state = run("confirm", facts, permissions=frozenset())
contains("refused without the grant", state.get("generation"), "permission")
after = fact_store.get(CID, force=True)
check("nothing was deducted", after.by_barcode("89010002").quantity, 100)


print("\n== A question about the same products is still a question ==")
pending_actions.clear(CID, SID)
facts = testkit.seed()
for question in (
    "show me all low stock items",
    "what is low stock",
    "give me the reorder list",
    "which products are out of stock",
):
    state = run(question, facts)
    ok = state.get("intent") != "EXECUTION" or state.get("response_kind") != "bulk_preview"
    if not ok:
        _failures.append(f"{question!r} was treated as a bulk write")
    print(f"  {'PASS' if ok else 'FAIL'}  not a write: {question!r}")


print("\n== A single-product request is untouched by any of this ==")
pending_actions.clear(CID, SID)
facts = testkit.seed()
check("not seen as bulk", bulk.is_bulk_write("add 50 units of Fresh Apples"), False)
check("nor is a new product", bulk.is_bulk_write("add a new product called Bread"), False)


print("\n== The bulk cap keeps one message from rewriting a whole catalog ==")
big = testkit.seed([
    {"id": f"p{i}", "barcode": f"BC{i:04d}", "name": f"Item {i}", "stock": 1,
     "min_threshold": 10, "category": "General", "cost_price": 1.0,
     "selling_price": 2.0}
    for i in range(bulk.MAX_BULK_TARGETS + 25)
])
plan = bulk.parse("add 1 unit to all low stock products", big)
check("capped", plan.count, bulk.MAX_BULK_TARGETS)
check("remembers the real total", plan.truncated_from, bulk.MAX_BULK_TARGETS + 25)
contains("says so in the preview", bulk.preview(plan, big), "capped this at")


print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(" -", f)
    sys.exit(1)
print("All bulk tests passed.")
