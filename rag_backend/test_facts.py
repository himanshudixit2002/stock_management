"""Regression tests for the fact layer.

The headline assertion is Dart parity: `daily_burn_rate`, `days_of_supply` and
the health quadrant must match
`report_analytics_service.dart::computeInventoryHealthForecasts`, because the
assistant and the app's Reports screen have to quote the same numbers.
"""

import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, ".")

from facts import InventoryFacts, derive_product_fact

NOW = datetime(2026, 6, 1, tzinfo=timezone.utc)
WINDOW = 90

_failures = []


def check(label, actual, expected):
    ok = actual == expected
    if not ok:
        _failures.append(f"{label}: expected {expected!r}, got {actual!r}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual!r}")


def close(label, actual, expected, tol=1e-6):
    ok = abs(actual - expected) <= tol
    if not ok:
        _failures.append(f"{label}: expected ~{expected}, got {actual}")
    print(f"  {'PASS' if ok else 'FAIL'}  {label}: {actual}")


def product(**over):
    base = {
        "id": "p1",
        "barcode": "1001",
        "name": "Test Widget",
        "quantity": 100,
        "heldQuantity": 0,
        "lowStockThreshold": 10,
        "costPrice": 4.0,
        "sellingPrice": 10.0,
        "categoryName": "General",
        "locationQuantities": {"Main": 100},
        "preferredVendorId": "v1",
    }
    base.update(over)
    return base


def tx(days_ago, qty, kind="stock_out"):
    return (NOW - timedelta(days=days_ago), kind, qty)


VENDORS = {"v1": {"name": "Acme", "leadTimeDays": 7}}


print("\n== Dart parity: burn rate and days of supply ==")
# 180 units out over the 90 day window -> 2.0/day; 100 on hand -> 50 days cover.
history = {"p1": [tx(d, 2) for d in range(1, 91)]}
f = derive_product_fact(product(), history, VENDORS, WINDOW, NOW)
check("units_out_window", f.units_out_window, 180)
close("daily_burn_rate (180/90)", f.daily_burn_rate, 2.0)
close("days_of_supply (100/2)", f.days_of_supply, 50.0)
check("health", f.health, "optimal")
check("lead_time from vendor", f.lead_time_days, 7)

print("\n== Dart parity: no movement -> dead stock, 999 cover ==")
f = derive_product_fact(product(), {}, VENDORS, WINDOW, NOW)
close("daily_burn_rate", f.daily_burn_rate, 0.0)
close("days_of_supply", f.days_of_supply, 999.0)
check("health", f.health, "dead_stock")

print("\n== Dart parity: zero stock -> at risk, 0 cover ==")
f = derive_product_fact(product(quantity=0), {}, VENDORS, WINDOW, NOW)
close("days_of_supply", f.days_of_supply, 0.0)
check("health", f.health, "at_risk")

print("\n== Dart parity: under 14 days cover -> at risk ==")
# 900 out over 90 days = 10/day; 50 on hand = 5 days.
f = derive_product_fact(
    product(quantity=50), {"p1": [tx(d, 10) for d in range(1, 91)]}, VENDORS, WINDOW, NOW
)
close("daily_burn_rate", f.daily_burn_rate, 10.0)
close("days_of_supply", f.days_of_supply, 5.0)
check("health", f.health, "at_risk")

print("\n== Dart parity: over 90 days cover + qty > 15 -> overstocked ==")
# 90 out over 90 days = 1/day; 500 on hand = 500 days.
f = derive_product_fact(
    product(quantity=500), {"p1": [tx(d, 1) for d in range(1, 91)]}, VENDORS, WINDOW, NOW
)
check("health", f.health, "overstocked")

print("\n== Available-to-promise excludes held stock ==")
f = derive_product_fact(
    product(quantity=100, heldQuantity=40),
    {"p1": [tx(d, 2) for d in range(1, 91)]},
    VENDORS,
    WINDOW,
    NOW,
)
check("quantity", f.quantity, 100)
check("held_quantity", f.held_quantity, 40)
check("available_qty (100-40)", f.available_qty, 60)
close("days_of_supply_available (60/2)", f.days_of_supply_available, 30.0)

print("\n== Transactions outside the window are ignored ==")
f = derive_product_fact(
    product(), {"p1": [tx(200, 500), tx(5, 10)]}, VENDORS, WINDOW, NOW
)
check("units_out_window (only the in-window one)", f.units_out_window, 10)

print("\n== Damage counts as consumption, stock_in does not ==")
f = derive_product_fact(
    product(),
    {"p1": [tx(5, 10, "stock_out"), tx(6, 5, "damage"), tx(7, 50, "stock_in")]},
    VENDORS,
    WINDOW,
    NOW,
)
check("units_out_window (10 sold + 5 damaged)", f.units_out_window, 15)
check("units_in_window", f.units_in_window, 50)

print("\n== Demand sigma is real, not avg*0.3 ==")
# Spiky demand: 60 units on one day, nothing else.
f = derive_product_fact(
    product(), {"p1": [tx(5, 60)]}, VENDORS, WINDOW, NOW
)
spiky_sigma = f.demand_std_dev
# Smooth demand: same total spread evenly.
f2 = derive_product_fact(
    product(), {"p1": [tx(d, 2) for d in range(1, 31)]}, VENDORS, WINDOW, NOW
)
smooth_sigma = f2.demand_std_dev
ok = spiky_sigma > smooth_sigma
if not ok:
    _failures.append("sigma should be higher for spiky demand")
print(f"  {'PASS' if ok else 'FAIL'}  spiky sigma {spiky_sigma} > smooth sigma {smooth_sigma}")

print("\n== Reorder point respects lead time and sigma ==")
f = derive_product_fact(
    product(quantity=20), {"p1": [tx(d, 5) for d in range(1, 91)]}, VENDORS, WINDOW, NOW
)
close("daily_burn_rate", f.daily_burn_rate, 5.0)
ok = f.reorder_point >= 35  # 5/day * 7 day lead time, plus safety stock
if not ok:
    _failures.append(f"reorder_point too low: {f.reorder_point}")
print(f"  {'PASS' if ok else 'FAIL'}  reorder_point {f.reorder_point} >= 35 (5/day x 7d lead + safety)")
check("needs_reorder (20 on hand)", f.needs_reorder, True)
ok = f.suggested_reorder_qty > 0
print(f"  {'PASS' if ok else 'FAIL'}  suggested_reorder_qty {f.suggested_reorder_qty} > 0")

print("\n== Missing vendor falls back to the default lead time ==")
f = derive_product_fact(product(preferredVendorId=""), {}, {}, WINDOW, NOW)
check("lead_time_days", f.lead_time_days, 3)

print("\n== Fingerprint changes when stock changes ==")
a = InventoryFacts("c", 0, 0.0, WINDOW, [derive_product_fact(product(), {}, VENDORS, WINDOW, NOW)]).index()
b = InventoryFacts("c", 0, 0.0, WINDOW, [derive_product_fact(product(), {}, VENDORS, WINDOW, NOW)]).index()
c = InventoryFacts("c", 0, 0.0, WINDOW, [derive_product_fact(product(quantity=99), {}, VENDORS, WINDOW, NOW)]).index()
check("identical inventory -> same fingerprint", a.fingerprint == b.fingerprint, True)
check("changed stock -> different fingerprint", a.fingerprint == c.fingerprint, False)

print("\n== Sparse ledger: 'no movement' must not be read as 'not selling' ==")
# A 600-SKU catalog where nothing has ever been recorded says everything about
# the record keeping and nothing about demand.
sparse = InventoryFacts(
    "c", 0, 0.0, WINDOW,
    [derive_product_fact(product(id=f"p{i}", barcode=f"b{i}"), {}, VENDORS, WINDOW, NOW)
     for i in range(20)],
).index()
check("coverage is zero", sparse.history_coverage, 0.0)
check("history flagged unreliable", sparse.history_is_reliable, False)
check("nothing labelled dead stock", sparse.summary()["dead_stock_count"], 0)
check("all 20 marked untracked instead", sparse.summary()["untracked_count"], 20)
contains_note = "NOT BEING TRACKED" in sparse.summary_line()
check("summary warns the model off a dead-stock reading", contains_note, True)

# With real movement across the catalog, dead stock is a fair call again.
dense = InventoryFacts(
    "c", 0, 0.0, WINDOW,
    [derive_product_fact(product(id=f"m{i}", barcode=f"m{i}"),
                         {f"m{i}": [tx(d, 2) for d in range(1, 91)]}, VENDORS, WINDOW, NOW)
     for i in range(9)]
    + [derive_product_fact(product(id="stale", barcode="stale"), {}, VENDORS, WINDOW, NOW)],
).index()
check("coverage is high", round(dense.history_coverage, 2), 0.9)
check("history flagged reliable", dense.history_is_reliable, True)
check("the one non-mover is genuine dead stock", dense.summary()["dead_stock_count"], 1)

print("\n== Summary aggregates ==")
facts = InventoryFacts(
    "c", 0, 0.0, WINDOW,
    [
        derive_product_fact(product(id="a", barcode="a", quantity=0), {}, VENDORS, WINDOW, NOW),
        derive_product_fact(product(id="b", barcode="b", quantity=5, lowStockThreshold=10), {}, VENDORS, WINDOW, NOW),
        derive_product_fact(product(id="c", barcode="c", quantity=100), {"c": [tx(d, 2) for d in range(1, 91)]}, VENDORS, WINDOW, NOW),
    ],
).index()
s = facts.summary()
check("total_products", s["total_products"], 3)
check("out_of_stock_count", s["out_of_stock_count"], 1)
check("low_stock_count", s["low_stock_count"], 1)
check("has_sales_history (product c moved)", s["has_sales_history"], True)

print("\n" + "=" * 60)
if _failures:
    print(f"{len(_failures)} FAILURE(S):")
    for f_ in _failures:
        print(f"  - {f_}")
    sys.exit(1)
print("All fact-layer tests passed.")
