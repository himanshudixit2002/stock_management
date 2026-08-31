"""End-to-end pipeline tests that need no LLM and no Firestore.

Covers the paths that used to be broken:
  * routing (the old router defaulted every ambiguous question to KNOWLEDGE)
  * the EXECUTION context block (the old code branched on an intent literal the
    router never emitted, so the action agent got no product data at all)
  * confirm-before-write, executed from server-side structured state instead of
    by regex-scraping a previously rendered markdown table
"""

import asyncio
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, ".")

import deterministic
from facts import InventoryFacts, derive_product_fact
from graph import rag_pipeline
from inventory_db import db_instance
from nodes import retrieve_node, router_node, sanitize_history
from pending import pending_actions

NOW = datetime.now(timezone.utc)
WINDOW = 90
CID = "test_co"
SID = "test_session"

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


def raw(pid, barcode, name, qty, threshold=10, held=0, cost=4.0, price=10.0):
    return {
        "id": pid,
        "barcode": barcode,
        "name": name,
        "quantity": qty,
        "heldQuantity": held,
        "lowStockThreshold": threshold,
        "costPrice": cost,
        "sellingPrice": price,
        "categoryName": "General",
        "locationQuantities": {"Main": qty},
        "preferredVendorId": "v1",
    }


def outs(per_day, days=90):
    return [(NOW - timedelta(days=d), "stock_out", per_day) for d in range(1, days + 1)]


VENDORS = {"v1": {"name": "Acme Supplies", "leadTimeDays": 7}}
HISTORY = {
    "p_cannula18": outs(3),   # 3/day
    "p_cannula20": outs(1),   # 1/day
    "p_gauze": outs(10),      # 10/day, will be critical
    # p_dead has no movement at all
}
RAW = [
    raw("p_cannula18", "1001", "Cannula 18G", 200),
    raw("p_cannula20", "1002", "Cannula 20G", 300),
    raw("p_gauze", "2002", "Sterile Gauze Pad", 30, threshold=50),
    raw("p_dead", "3003", "Vintage Ledger Book", 80, cost=12.0, price=25.0),
    raw("p_held", "4004", "Reserved Syringe 5ml", 100, held=70),
]

FACTS = InventoryFacts(
    company_id=CID,
    version=1,
    generated_at=0.0,
    window_days=WINDOW,
    products=[derive_product_fact(r, HISTORY, VENDORS, WINDOW, NOW) for r in RAW],
).index()

# Seed the local store so offline writes have something to act on.
db_instance.replace_user_inventory(
    [
        {
            "id": r["id"],
            "barcode": r["barcode"],
            "name": r["name"],
            "stock": r["quantity"],
            "min_threshold": r["lowStockThreshold"],
            "cost_price": r["costPrice"],
            "selling_price": r["sellingPrice"],
        }
        for r in RAW
    ],
    company_id=CID,
)


def run(question, history=None):
    return asyncio.run(
        rag_pipeline.ainvoke(
            {
                "question": question,
                "retries": 0,
                "history": history or [],
                "company_id": CID,
                "business_type": "clinic",
                "session_id": SID,
                "facts": FACTS,
            }
        )
    )


def route(question):
    return asyncio.run(
        router_node({"question": question, "company_id": CID, "session_id": SID})
    )["intent"]


print("\n== Derived facts are sane before anything else ==")
gauze = FACTS.by_barcode("2002")
check("gauze burn rate 10/day", gauze.daily_burn_rate, 10.0)
check("gauze 3 days of cover", gauze.days_of_supply, 3.0)
check("gauze at risk", gauze.health, "at_risk")
check("gauze needs reorder", gauze.needs_reorder, True)
check("ledger book is dead stock", FACTS.by_barcode("3003").health, "dead_stock")
check("held stock excluded from available", FACTS.by_barcode("4004").available_qty, 30)

print("\n== Routing: mutations, analytics, and the ambiguous tail ==")
check("'add 50 cannula 18g'", route("add 50 cannula 18g"), "EXECUTION")
check("'deduct 5 units of gauze'", route("deduct 5 units of gauze"), "EXECUTION")
check("'set threshold to 100'", route("set the threshold to 100"), "EXECUTION")
check("'show low stock'", route("show low stock"), "ANALYTICS")
check("'what should I order next'", route("what should I order next"), "ANALYTICS")
check("'what runs out first'", route("what runs out first"), "ANALYTICS")
check("'hello'", route("hello"), "KNOWLEDGE")

print("\n== EXECUTION now receives the matching products (the old dead branch) ==")
state = asyncio.run(
    retrieve_node(
        {
            "question": "add 50 units of cannula 18g",
            "intent": "EXECUTION",
            "company_id": CID,
            "facts": FACTS,
        }
    )
)
block = state["context_block"]
contains("context names the product", block, "Cannula 18G")
contains("context carries the barcode", block, "1001")
contains("context carries live stock", block, "stock 200")
ok = len(state["focus"]) > 0
if not ok:
    _failures.append("EXECUTION focus list is empty")
print(f"  {'PASS' if ok else 'FAIL'}  focus resolved to {len(state['focus'])} product(s)")

print("\n== Deterministic answers, zero tokens ==")
res = run("show me low stock items")
check("answered without a model", res["answered_by"], "deterministic")
contains("lists the gauze", res["generation"], "Sterile Gauze Pad")

res = run("what runs out first")
check("stockout projection is deterministic", res["answered_by"], "deterministic")
contains("names the fastest burner", res["generation"], "Sterile Gauze Pad")
contains("gives a lead-time warning", res["generation"], "lead time")

res = run("what isn't selling")
contains("dead stock names the ledger book", res["generation"], "Vintage Ledger Book")
contains("dead stock quantifies trapped capital", res["generation"], "960")

res = run("what should I order next")
contains("reorder list names the gauze", res["generation"], "Sterile Gauze Pad")
contains("reorder list gives a quantity", res["generation"], "+")

res = run("how much is my inventory worth")
contains("valuation includes retail value", res["generation"], "Retail value")

res = run("run an inventory audit")
contains("audit reports dead stock", res["generation"], "Dead Stock")

print("\n== Single-product lookup resolves rather than substring-matches ==")
res = run("how many sterile gauze pad do i have")
contains("names the right product", res["generation"], "Sterile Gauze Pad")
contains("reports live stock", res["generation"], "30")

print("\n== An ambiguous lookup asks instead of guessing ==")
res = run("how many cannula do i have")
contains("offers 18G", res["generation"], "Cannula 18G")
contains("offers 20G", res["generation"], "Cannula 20G")
contains("asks the user", res["generation"], "which one")
check("answered without a model", res["answered_by"], "deterministic")
options = res.get("clarification_options") or []
check("candidates returned for tappable chips", len(options), 2)
check(
    "each option carries a barcode the client can reply with",
    all(o.get("barcode") for o in options),
    True,
)

print("\n== Picking a product keeps the action that asked the question ==")
# Duplicate names are common in real catalogs. Answering "which one?" with a
# barcode carries no quantity, so the original request has to survive or the
# user's intent is silently dropped.
testkit_dupes = [
    {"id": "d1", "barcode": "700001", "name": "Cotton Roll Basic", "stock": 90, "min_threshold": 10},
    {"id": "d2", "barcode": "700002", "name": "Cotton Roll Basic", "stock": 16, "min_threshold": 10},
]
db_instance.replace_user_inventory(testkit_dupes, company_id="dupe_co")
from facts import fact_store as _fs
_fs.bump("dupe_co")

def run_dupe(q, sid="dupe_sess"):
    return asyncio.run(rag_pipeline.ainvoke({
        "question": q, "retries": 0, "history": [], "company_id": "dupe_co",
        "business_type": "clinic", "session_id": sid,
    }))

res = run_dupe("add 12 units of Cotton Roll Basic")
check("identical names are ambiguous", res["response_kind"], "clarification")
check("both offered", len(res.get("clarification_options") or []), 2)

res = run_dupe("700002")
check("picking a barcode resumes the action", res["response_kind"], "preview")
contains("previews the right product", res["generation"], "700002")
contains("keeps the original quantity", res["generation"], "12")
check("nothing written yet", res.get("executed_actions"), [])

res = run_dupe("confirm")
check("confirming applies it", res["response_kind"], "executed")
acts = res.get("executed_actions") or []
check("stock moved 16 -> 28", acts[0]["result"].get("new_stock") if acts else None, 28)

print("\n== Confirm-before-write executes the previewed action exactly ==")
pending_actions.put(
    CID,
    SID,
    {
        "tool": "update_stock",
        "args": {"qty_change": 25, "reason": "test top-up"},
        "barcode": "2002",
        "product_id": "p_gauze",
        "product_name": "Sterile Gauze Pad",
    },
)
res = run("confirm")
check("executed from pending state", res["answered_by"], "pending")
actions = res.get("executed_actions") or []
check("one action executed", len(actions), 1)
check("it succeeded", actions[0]["result"].get("success"), True)
check("stock moved 30 -> 55", actions[0]["result"].get("new_stock"), 55)
check("pending cleared afterwards", pending_actions.get(CID, SID), None)

print("\n== Cancelling changes nothing ==")
pending_actions.put(
    CID,
    SID,
    {
        "tool": "update_stock",
        "args": {"qty_change": -999, "reason": "should never run"},
        "barcode": "2002",
        "product_id": "p_gauze",
        "product_name": "Sterile Gauze Pad",
    },
)
res = run("cancel")
contains("says it cancelled", res["generation"], "cancelled")
check("no actions executed", res.get("executed_actions"), [])
check("pending cleared", pending_actions.get(CID, SID), None)

print("\n== A bare 'confirm' with nothing pending never mutates ==")
res = run("confirm")
check("no action executed", res.get("executed_actions") or [], [])

print("\n== Every answer declares how it should be rendered ==")
check("a report", run("show me low stock items")["response_kind"], "report")
check("a product lookup", run("how many sterile gauze pad do i have")["response_kind"], "product_detail")
check("an ambiguity", run("how many cannula do i have")["response_kind"], "clarification")
pending_actions.put(CID, SID, {
    "tool": "update_stock", "args": {"qty_change": 1, "reason": "kind check"},
    "barcode": "2002", "product_id": "p_gauze", "product_name": "Sterile Gauze Pad",
})
check("an executed action", run("confirm")["response_kind"], "executed")

print("\n== History is trimmed: tables stripped, turns capped ==")
bulky = [
    {"role": "user", "content": "show audit"},
    {
        "role": "model",
        "content": "Here is your audit:\n\n| Product | Stock |\n| :--- | :--- |\n| A | 1 |\n| B | 2 |\n\nThat's everything.\n\n[STATS: {\"total\": 5}]",
    },
]
msgs = sanitize_history(bulky)
joined = " ".join(str(m.content) for m in msgs)
check("table rows removed", "| A | 1 |" in joined, False)
check("stats block removed", "[STATS:" in joined, False)
check("prose kept", "That's everything." in joined, True)
check("turn cap honoured", len(sanitize_history([{"role": "user", "content": f"m{i}"} for i in range(50)])), 12)

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All pipeline tests passed.")
