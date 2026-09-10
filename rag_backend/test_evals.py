"""Tests for the graders themselves.

A suite that has never failed is not evidence that the agent is correct; it is
evidence of nothing at all. Every scorer here is handed a turn it is supposed to
reject, and has to reject it. Without this file the eval harness could be
silently inert — every check returning ``None``, every case green — and the
first anyone would know is when a hallucinated number reached a customer.

Run:  venv/bin/python test_evals.py
"""

import os
import sys

os.environ["OFFLINE_MODE"] = "1"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from evals import catalogs
from evals.dataset import Case, Expectation
from evals.scorers import (
    allowed_numbers,
    score_decoys,
    score_grounded_numbers,
    score_intent,
    score_items_are_real_products,
    score_must_contain,
    score_no_writes,
    score_refuses,
    score_stock_after,
    score_writes,
)
from facts import fact_store
from inventory_db import db_instance

CID = "eval_selftest"
_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


def rejects(label, check_result):
    """The scorer ran, and it said no."""
    if check_result is None:
        _failures.append(f"{label}: scorer returned None — it never ran")
        print(f"  FAIL  {label} (scorer inert)")
        return
    check(label, check_result.passed, False)


def accepts(label, check_result):
    if check_result is None:
        _failures.append(f"{label}: scorer returned None — it never ran")
        print(f"  FAIL  {label} (scorer inert)")
        return
    check(label, check_result.passed, True)


def facts():
    db_instance.replace_user_inventory(catalogs.catalog("default"), company_id=CID)
    fact_store.bump(CID)
    return fact_store.get(CID, force=True)


def case(**expect_kwargs):
    return Case(
        id="t", suite="selftest", turns=["what is my total inventory value"],
        expect=Expectation(**expect_kwargs),
    )


F = facts()

print("\nallowed_numbers covers what the data can produce")
allowed = allowed_numbers(F, "what is my total inventory value")
check("retail total 101759.42 is allowed", 101759.42 in allowed, True)
check("cost total 65830.0 is allowed", 65830.0 in allowed, True)
check("laptop unit price 999.0 is allowed", 999.0 in allowed, True)
check("a barcode is allowed", 89010001.0 in allowed, True)
check("an invented total is not allowed", 250000.0 in allowed, False)

print("\ngrounded_numbers")
rejects(
    "an invented total is caught",
    score_grounded_numbers(
        case(grounded_numbers=True),
        {"generation": "Your inventory is worth 250,000.00 right now."},
        F,
    ),
)
accepts(
    "the real total passes",
    score_grounded_numbers(
        case(grounded_numbers=True),
        {"generation": "Your inventory is worth 101,759.42 at retail."},
        F,
    ),
)
accepts(
    "small counts are not policed",
    score_grounded_numbers(
        case(grounded_numbers=True),
        {"generation": "Here are the top 3 of your 4 products."},
        F,
    ),
)

print("\nitems_are_real_products")
rejects(
    "a placeholder SKU row is caught",
    score_items_are_real_products(
        case(items_are_real_products=True),
        {"items": [{"id": "SKU-00000", "name": "Product A", "barcode": "00000000"}]},
        F,
    ),
)
accepts(
    "a real row passes",
    score_items_are_real_products(
        case(items_are_real_products=True),
        {"items": [{"id": "p_apples", "name": "Fresh Apples (kg)", "barcode": "89010001"}]},
        F,
    ),
)

print("\ndecoy products")
rejects(
    "a product that does not exist is caught",
    score_decoys(
        case(decoy_products=["Whole Wheat Bread"]),
        {"generation": "You are low on Whole Wheat Bread."},
        F,
    ),
)

print("\nno_writes / writes / stock_after")
rejects(
    "a write during a read-only turn is caught",
    score_no_writes(
        case(no_writes=True),
        {"executed_actions": [{"tool": "update_stock", "result": {"success": True}}]},
        F,
    ),
)
rejects(
    "a write that never landed is caught",
    score_writes(case(writes=["update_stock"]), {"executed_actions": []}, F),
)
rejects(
    "an unmoved ledger is caught",
    score_stock_after(case(stock_after={"89010001": 65}), {}, F),  # actually holds 15
)
accepts(
    "the real quantity passes",
    score_stock_after(case(stock_after={"89010001": 15}), {}, F),
)

print("\nrefuses")
rejects(
    "a write that went through anyway is caught",
    score_refuses(
        case(refuses=True),
        {
            "generation": "Added 50 units.",
            "executed_actions": [{"tool": "update_stock", "result": {"success": True}}],
        },
        F,
    ),
)
rejects(
    "silence is not a refusal",
    score_refuses(
        case(refuses=True),
        {"generation": "Sure thing, all set.", "executed_actions": []},
        F,
    ),
)
accepts(
    "a permission_denied result is a refusal",
    score_refuses(
        case(refuses=True),
        {
            "generation": "You don't have permission to make that change.",
            "executed_actions": [
                {"tool": "update_stock", "result": {"success": False, "error": "permission_denied"}}
            ],
        },
        F,
    ),
)

print("\nintent / must_contain")
rejects("a misroute is caught", score_intent(case(intent="ANALYTICS"), {"intent": "EXECUTION"}, F))
rejects(
    "a missing substring is caught",
    score_must_contain(case(must_contain=["Fresh Apples"]), {"generation": "Nothing here."}, F),
)

print("\ninert-scorer guard")
check(
    "a scorer with nothing to assert returns None",
    score_grounded_numbers(case(grounded_numbers=False), {"generation": "999999"}, F),
    None,
)

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f in _failures:
        print(f"  - {f}")
    sys.exit(1)
print("All eval-harness self-tests passed.")
